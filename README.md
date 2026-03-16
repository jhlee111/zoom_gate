# ZoomGate

Zoom Meeting SDK bridge — waiting room access control as a service.

ZoomGate wraps the [Zoom Native Meeting SDK](https://developers.zoom.us/docs/meeting-sdk/) (C++ on Linux) as an Elixir/OTP service, exposing meeting bot capabilities through three API layers.

## Why?

The Zoom REST API **cannot** manage waiting rooms — no admit, no deny, no rename. These features are only available through the Meeting SDK, which requires a process running inside the meeting.

ZoomGate solves this by running a headless bot that joins your meeting and gives you programmatic control over the waiting room.

## Features

- **Waiting room control** — admit, deny, rename, expel participants
- **Participant management** — list, monitor join/leave events
- **In-meeting chat** — send messages to participants
- **Three API layers** — use whichever fits your stack

## API Layers

| Layer | Protocol | Best for |
|-------|----------|----------|
| **BEAM Cluster** | distributed Erlang | Elixir/Erlang apps (zero overhead) |
| **WebSocket** | Phoenix Channel | Node.js, Python, Go, browsers |
| **REST + Webhooks** | HTTP | Any language/framework |

## Quick Start (Docker)

```bash
docker run -d \
  -e ZOOM_SDK_KEY=your_sdk_key \
  -e ZOOM_SDK_SECRET=your_sdk_secret \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -p 4000:4000 \
  zoomgate/zoomgate:latest
```

## Usage

### BEAM Cluster (Elixir)

```elixir
# Join a meeting with a bot
{:ok, _pid} = ZoomGate.join_meeting("123456789",
  sdk_key: "...",
  sdk_secret: "...",
  callback: self()
)

# Receive waiting room events
receive do
  {:zoom_gate, {:waiting_room_join, %{zoom_user_id: zid, display_name: name}}} ->
    ZoomGate.admit("123456789", zid, display_name: "Approved Name")
end
```

### WebSocket (JavaScript)

```javascript
import { Socket } from "phoenix"

const socket = new Socket("ws://localhost:4000/ws/gate", {
  params: { api_key: "zg_live_xxx" }
})
socket.connect()

const channel = socket.channel("gate:123456789")
channel.join()

channel.on("waiting_room_join", ({ zoom_user_id, display_name }) => {
  channel.push("admit", { zoom_user_id, display_name: "Approved Name" })
})
```

### REST + Webhooks

```bash
# Start a bot session
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer zg_live_xxx" \
  -H "Content-Type: application/json" \
  -d '{"meeting_id":"123456789","webhook_url":"https://your-app.com/webhooks/zoomgate"}'

# Admit a participant
curl -X POST http://localhost:4000/api/sessions/123456789/admit \
  -H "Authorization: Bearer zg_live_xxx" \
  -H "Content-Type: application/json" \
  -d '{"zoom_user_id":12345,"display_name":"Approved Name"}'
```

## Architecture

```
ZoomGate (Elixir/OTP)
├── SessionSupervisor (DynamicSupervisor)
│   └── Session (GenServer) × N     ← one per active meeting
│       └── Port → zoom_worker      ← C++ binary (Zoom Native SDK)
├── API
│   ├── BEAM Cluster (GenServer.call)
│   ├── WebSocket (Phoenix Channel)
│   └── REST (Plug Router)
└── Registry (meeting_id → Session PID)
```

## Development

```bash
mix deps.get
mix compile
mix test
```

## Requirements

- Elixir 1.18+
- Zoom Meeting SDK App (SDK Key + Secret) — [Create here](https://marketplace.zoom.us/)
- Linux x86_64 for the C++ worker (Docker handles this)

## License

MIT
