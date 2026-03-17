# Error Reference

This guide covers all error responses and failure modes across ZoomGate's
three API layers: REST, WebSocket, and BEAM.

## HTTP Status Codes (REST API)

| Status | Meaning | When |
|--------|---------|------|
| 200 | Success | Command executed, resource returned |
| 201 | Created | Session started (POST /sessions) |
| 401 | Unauthorized | Invalid or missing `Authorization: Bearer` token |
| 404 | Not Found | Session does not exist, or unknown route |
| 422 | Unprocessable Entity | Validation error or session start failed |

## Error Response Format

All REST errors return JSON:

```json
{"error": "description of what went wrong"}
```

The `error` field is always a string. The HTTP status code indicates the
error category.

## Session Start Errors

These occur when calling `ZoomGate.join_meeting/2` or `POST /api/sessions`.

### Already Started

```elixir
ZoomGate.join_meeting("123456789", opts)
# => {:ok, #PID<0.456.0>}  (returns existing PID, not an error)
```

If a session already exists for the meeting ID, `join_meeting/2` returns
`{:ok, pid}` with the existing session's PID. This is not an error -- it
is idempotent.

### Max Sessions Reached

```elixir
ZoomGate.join_meeting("999999999", opts)
# => {:error, :max_sessions_reached}
```

The `ZOOM_GATE_MAX_SESSIONS` limit (default: 100) has been reached.
Terminate an existing session before starting a new one.

REST response:

```
HTTP/1.1 422 Unprocessable Entity

{"error": ":max_sessions_reached"}
```

### MeetingBot Failed to Start

```elixir
ZoomGate.join_meeting("123456789", opts)
# => {:error, {:meeting_bot_failed, reason}}
```

The MeetingBot GenServer could not start. Common causes:

| Reason | Cause |
|--------|-------|
| Connection timeout | Zoom RWG server unreachable or DNS failure |
| WebSocket upgrade rejected | Invalid SDK credentials or meeting not found |
| Invalid SDK key/secret | JWT signature verification failed on Zoom's side |

REST response:

```
HTTP/1.1 422 Unprocessable Entity

{"error": "{:meeting_bot_failed, :ws_timeout}"}
```

### Missing Meeting ID

```
HTTP/1.1 422 Unprocessable Entity

{"error": "meeting_id is required"}
```

The `meeting_id` field was not provided in the POST body.

### Zoom SDK Errors

If the bot connects but Zoom rejects the join request:

```
"Meeting info error 200: JOIN_MEETING_FAILED"
```

Common causes:

| Error | Cause | Fix |
|-------|-------|-----|
| `JOIN_MEETING_FAILED` (200) | Invalid or expired ZAK token | Refresh ZAK via OAuth before joining |
| `JOIN_MEETING_FAILED` (200) | Meeting does not exist | Verify the meeting ID |
| `JOIN_MEETING_FAILED` (200) | Meeting has not started | Wait for the host to start the meeting |
| Invalid signature | SDK key/secret mismatch | Check `ZOOM_SDK_KEY` and `ZOOM_SDK_SECRET` |

## Runtime Errors

These occur during an active session and are delivered as `:error` events
through all event channels (callback, PubSub, subscribers, webhook).

### Event Format

```elixir
{:zoom_gate, {:error, %{message: "description"}}}
```

Webhook format:

```json
{
  "event": "error",
  "data": {"message": "description"},
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Common Runtime Errors

| Error | Description |
|-------|-------------|
| Connection drop | WebSocket to Zoom RWG disconnected unexpectedly |
| Protocol error | Malformed message from Zoom (unexpected frame format) |
| Heartbeat timeout | Zoom RWG server stopped responding to keepalive |

### Command Failures

Most commands that target a specific `zoom_user_id` do not return errors
from Zoom. If you attempt to admit a user who has already left the waiting
room, or expel a user who is not in the meeting, the command is **silently
ignored** by Zoom's servers. ZoomGate returns `:ok` regardless.

There is no way to distinguish "command accepted" from "command ignored" at
the ZoomGate layer. Track participant state via events to avoid sending
commands for users who are no longer present.

## Authentication Errors

### REST API (401)

```bash
curl -X GET http://localhost:4000/api/sessions \
  -H "Authorization: Bearer wrong_key"
```

```
HTTP/1.1 401 Unauthorized

{"error": "unauthorized"}
```

This only occurs when `ZOOM_GATE_API_KEY` is configured. If no API key is
set, all requests pass through.

### WebSocket

If the `api_key` connection param is missing or wrong, the WebSocket
connection is rejected. The client receives a transport-level error (no
JSON error body).

```javascript
// Phoenix JS client
socket.onError((error) => console.log("Connection failed:", error))
```

### Channel Join (WebSocket)

Attempting to join a channel for a non-existent session:

```javascript
channel.join()
  .receive("error", (resp) => {
    // resp = {reason: "no active session for meeting 123456789"}
  })
```

## GenServer Errors (BEAM API)

When calling ZoomGate functions directly from Elixir code, you may encounter
standard OTP errors.

### No Process

```elixir
ZoomGate.admit("999999999", 12345)
# ** (exit) no process: the process is not alive or there's no process
#    currently associated with the given name
```

The session for this meeting ID does not exist (never started, already
ended, or terminated). Use `ZoomGate.Session.whereis/1` to check before
calling:

```elixir
case ZoomGate.Session.whereis(meeting_id) do
  nil -> {:error, :no_session}
  _pid -> ZoomGate.admit(meeting_id, zoom_user_id)
end
```

### Timeout

```elixir
ZoomGate.get_status("123456789")
# ** (exit) exited in: GenServer.call(...)
#    ** (EXIT) time out
```

The default `GenServer.call` timeout is **5000ms**. This can occur if the
Session GenServer is overloaded or blocked. In practice this is rare since
commands are simple message passes to the MeetingBot.

### Session Terminated During Call

```elixir
ZoomGate.admit("123456789", 12345)
# ** (exit) exited in: GenServer.call(...)
#    ** (EXIT) shutdown
```

The session terminated (meeting ended or MeetingBot crashed) while your
call was in flight. Wrap calls in `try/catch` if you need graceful handling:

```elixir
try do
  ZoomGate.admit(meeting_id, zoom_user_id)
catch
  :exit, _ -> {:error, :session_terminated}
end
```

## Error Handling Best Practices

1. **Check session existence** before sending commands (REST returns 404,
   BEAM raises exit). Use `Session.whereis/1` or `GET /api/sessions/:id`.

2. **Handle `:meeting_ended` events** promptly. Once received, the session
   is about to terminate. Any subsequent commands will fail.

3. **Wrap BEAM calls in try/catch** for resilience. Sessions can terminate
   at any moment due to meeting end or MeetingBot crash.

4. **Do not retry commands blindly.** If a command fails because the session
   is gone, retrying will not help. Check if the meeting is still active
   and create a new session if needed.

5. **Monitor session health** via `GET /health` for overall system status,
   and `GET /api/sessions/:id` for individual session status.
