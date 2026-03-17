# Webhook Delivery

ZoomGate can deliver session events to an HTTP endpoint via webhooks.
This is the simplest integration path for non-Elixir consumers that
do not want to maintain a persistent WebSocket connection.

## Setup

Provide a `webhook_url` when creating a session. All events for that
session will be POSTed to the URL.

**BEAM API:**

```elixir
ZoomGate.join_meeting("123456789",
  sdk_key: "...",
  sdk_secret: "...",
  zak: "...",
  webhook_url: "https://your-app.example.com/webhooks/zoom"
)
```

**REST API:**

```bash
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_id": "123456789",
    "webhook_url": "https://your-app.example.com/webhooks/zoom"
  }'
```

If `webhook_url` is not provided, no HTTP callbacks are made. Events are
still delivered via PubSub, subscriber messages, and callbacks.

## Delivery Format

Each event is sent as an HTTP POST with `Content-Type: application/json`:

```json
{
  "event": "waiting_room_join",
  "data": {
    "zoom_user_id": 12345,
    "display_name": "John"
  },
  "timestamp": "2024-01-15T10:30:00.000000Z"
}
```

The `event` field is a string version of the event atom. The `data` field
contains the event payload map. The `timestamp` is an ISO 8601 UTC datetime
generated at delivery time.

## Event Types

All session events are delivered via webhook:

| Event | Data Fields | Description |
|-------|------------|-------------|
| `bot_joined` | `meeting_id` | Bot joined the meeting successfully |
| `waiting_room_join` | `zoom_user_id`, `display_name` | User entered the waiting room |
| `waiting_room_leave` | `zoom_user_id` | User left the waiting room (admitted or left) |
| `participant_joined` | `zoom_user_id`, `display_name`, `role`, ... | User joined the active meeting |
| `participant_left` | `zoom_user_id` | User left the meeting |
| `participant_renamed` | `zoom_user_id`, `old_name`, `new_name` | User's display name changed |
| `chat_received` | `from_user_id`, `message` | Chat message received |
| `host_changed` | `new_host_id` | Host role transferred to another user |
| `meeting_ended` | `reason` | Meeting ended (normal, host action, or worker crash) |
| `error` | `message` | Error occurred in the session |

## Delivery Guarantees

Webhook delivery in ZoomGate is **fire-and-forget**:

- **Single attempt, no retries.** Each event is delivered exactly once. If the
  endpoint is unreachable or returns an error, the event is lost.
- **Non-blocking.** Webhook delivery runs in a detached `Task.start/1`. A slow
  or failing endpoint does not block event processing or affect the session.
- **No queue.** Events are not buffered. If your endpoint is down, events
  during the downtime are permanently missed.
- **HTTP client.** Uses Erlang's built-in `:httpc` module (from `:inets`). No
  external HTTP library dependency.
- **Success criteria.** Any 2xx response is considered successful. Non-2xx
  responses are logged as warnings but otherwise ignored.

### What Happens on Failure

| Scenario | Behavior |
|----------|----------|
| Endpoint returns 4xx/5xx | Warning logged, event discarded |
| Endpoint unreachable (DNS, connection refused) | Warning logged, event discarded |
| Endpoint times out | Warning logged, event discarded |
| Endpoint is slow (>30s) | `:httpc` default timeout applies |

## Recommendations for Reliable Delivery

Since ZoomGate does not retry or queue webhooks, consider these patterns
for production use:

1. **Use PubSub as a backup.** Subscribe to `"zoom_gate:MEETING_ID"` via
   `Phoenix.PubSub` within the BEAM cluster to ensure no events are lost,
   even if the webhook endpoint is temporarily down.

2. **Put a queue in front.** Use an intermediate webhook relay service
   (e.g., AWS SNS/SQS, Google Pub/Sub, or a self-hosted queue) that accepts
   the webhook POST and guarantees delivery to your application.

3. **Log all events.** If you have a PubSub subscriber in the cluster, write
   events to a persistent store (database, event log) as they arrive. Use
   webhooks for real-time notification and the log for reconciliation.

4. **Idempotent handlers.** Even though ZoomGate does not retry, your webhook
   handler should be idempotent. Duplicate deliveries are unlikely but possible
   if you run multiple ZoomGate instances or replay events from a log.

## Example Webhook Handler (Node.js)

```javascript
const express = require("express");
const app = express();
app.use(express.json());

app.post("/webhooks/zoom", (req, res) => {
  const { event, data, timestamp } = req.body;

  switch (event) {
    case "waiting_room_join":
      console.log(`${data.display_name} entered waiting room`);
      // Auto-admit logic, check against allowlist, etc.
      break;
    case "participant_joined":
      console.log(`${data.display_name} joined meeting`);
      break;
    case "meeting_ended":
      console.log(`Meeting ended: ${data.reason}`);
      break;
  }

  res.sendStatus(200);
});

app.listen(3000);
```
