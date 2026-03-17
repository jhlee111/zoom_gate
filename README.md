# ZoomGate

Zoom Meeting Bot Platform — waiting room access control as a service.

Pure Elixir WebSocket client (~10MB) that connects directly to Zoom's RWG servers. No C++ SDK, no browser, no Puppeteer.

## Why?

The Zoom REST API **cannot** manage waiting rooms — no admit, no deny, no rename. These features are only available through the Meeting SDK, which requires a process running inside the meeting.

ZoomGate solves this by running a lightweight bot that joins your meeting and gives you programmatic control.

## Features

- **Waiting room control** — admit, deny, admit_all, rename, expel
- **Participant management** — real-time join/leave events, mute
- **In-meeting chat** — send messages to participants
- **Meeting lifecycle** — join as host (ZAK), end meeting
- **Three API layers** — BEAM cluster, WebSocket, REST

## Quick Start

### Docker

```bash
docker run -d \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e ZOOM_GATE_API_KEY=my-secret-key \
  -p 4000:4000 \
  zoomgate/zoomgate:latest
```

### From Source

```bash
git clone https://github.com/jhlee111/zoom_gate
cd zoom_gate
mix deps.get
iex -S mix
```

## Usage

### BEAM Cluster (Elixir — zero overhead)

```elixir
# Join a meeting with a bot (as host with ZAK)
{:ok, _pid} = ZoomGate.join_meeting("123456789",
  sdk_key: "...",
  sdk_secret: "...",
  zak: "...",         # host join — get via Zoom OAuth API
  callback: self()
)

# Receive events
receive do
  {:zoom_gate, {:waiting_room_join, %{zoom_user_id: uid, display_name: name}}} ->
    ZoomGate.admit("123456789", uid)
end

# Or subscribe via PubSub (works across processes)
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:123456789")
```

### WebSocket (JavaScript)

```javascript
import { Socket } from "phoenix"

const socket = new Socket("ws://localhost:4000/ws/gate", {
  params: { api_key: "my-secret-key" }
})
socket.connect()

const channel = socket.channel("gate:123456789")
channel.join()

channel.on("waiting_room_join", ({ zoom_user_id, display_name }) => {
  channel.push("admit", { zoom_user_id })
})
```

### REST API

```bash
# Start a bot session (credentials per request)
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer my-secret-key" \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_id": "123456789",
    "sdk_key": "your_sdk_key",
    "sdk_secret": "your_sdk_secret",
    "zak": "zak_token_for_host_join"
  }'

# Admit from waiting room
curl -X POST http://localhost:4000/api/sessions/123456789/admit \
  -H "Authorization: Bearer my-secret-key" \
  -H "Content-Type: application/json" \
  -d '{"zoom_user_id": 12345}'

# All commands: admit, deny, rename, expel, chat, admit_all, mute, end_meeting
```

## API Reference

### REST Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/sessions` | Create bot session (join meeting) |
| `GET` | `/api/sessions` | List active sessions |
| `GET` | `/api/sessions/:id` | Session status + participants |
| `DELETE` | `/api/sessions/:id` | Leave meeting |
| `POST` | `/api/sessions/:id/admit` | Admit from waiting room |
| `POST` | `/api/sessions/:id/deny` | Deny from waiting room |
| `POST` | `/api/sessions/:id/admit_all` | Admit all from waiting room |
| `POST` | `/api/sessions/:id/rename` | Rename participant |
| `POST` | `/api/sessions/:id/expel` | Remove from meeting |
| `POST` | `/api/sessions/:id/mute` | Mute participant |
| `POST` | `/api/sessions/:id/chat` | Send chat message |
| `POST` | `/api/sessions/:id/end_meeting` | End meeting for all |
| `GET` | `/health` | Health check + session count |

### Events

| Event | Payload | When |
|-------|---------|------|
| `bot_joined` | `{meeting_id}` | Bot entered meeting |
| `waiting_room_join` | `{zoom_user_id, display_name}` | Someone entered WR |
| `waiting_room_leave` | `{zoom_user_id}` | Someone left WR (admitted) |
| `participant_joined` | `{zoom_user_id, display_name, role}` | Someone joined meeting |
| `participant_left` | `{zoom_user_id}` | Someone left meeting |
| `participant_renamed` | `{zoom_user_id, old_name, new_name}` | Name changed |
| `chat_received` | `{from_user_id, message}` | Chat message received |
| `host_changed` | `{new_host_id}` | Host role transferred |
| `meeting_ended` | `{reason}` | Meeting ended |

## Architecture

```
ZoomGate (Elixir/OTP)
├── SessionSupervisor (DynamicSupervisor)
│   └── Session (GenServer) × N        ← external API, event delivery
│       └── MeetingBot (GenServer)     ← RWG WebSocket, in-meeting control
│           ├── Connection             ← HTTP 3-step join flow
│           ├── Protocol               ← evt codes, encode/decode
│           └── Participant            ← roster tracking
├── API
│   ├── BEAM Cluster (:rpc.call)
│   ├── WebSocket (Phoenix Channel)
│   └── REST (Plug Router)
├── PubSub (Phoenix.PubSub)
└── Registry (meeting_id → Session PID)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY_BASE` | — | Phoenix secret (required in prod) |
| `ZOOM_GATE_API_KEY` | `nil` | Bearer token for API auth |
| `PORT` | `4000` | HTTP listen port |
| `ZOOM_GATE_MAX_SESSIONS` | `100` | Max concurrent bot sessions |
| `ZOOM_GATE_LOG_LEVEL` | `info` | Log level |
| `CLUSTER_STRATEGY` | `epmd` | Cluster: `epmd` / `dns` / `gossip` |
| `CLUSTER_HOSTS` | — | EPMD node list (comma-separated) |
| `RELEASE_COOKIE` | — | Erlang cookie for BEAM cluster |

Zoom credentials (sdk_key, sdk_secret, zak) are passed **per request**, not as global config. One ZoomGate instance can serve multiple Zoom accounts.

### BEAM Cluster

Connect an Elixir app (like GsNet) to ZoomGate via distributed Erlang:

```bash
# ZoomGate
RELEASE_NODE=zoom_gate@10.0.1.10
RELEASE_COOKIE=shared_secret
CLUSTER_HOSTS=gs_net@10.0.1.20

# Consumer app
RELEASE_NODE=gs_net@10.0.1.20
RELEASE_COOKIE=shared_secret
```

The consumer app passes Zoom credentials as opts — no API key needed (Erlang cookie is the auth):

```elixir
# 1. Join meeting — pass all credentials as opts
:rpc.call(:"zoom_gate@10.0.1.10", ZoomGate, :join_meeting, [
  "123456789",
  [
    sdk_key: "YOUR_CLIENT_ID",        # from Zoom Marketplace app
    sdk_secret: "YOUR_CLIENT_SECRET",  # from Zoom Marketplace app
    zak: "eyJ0eXAi...",               # fresh ZAK (fetch right before join)
    meeting_password: "123456",        # meeting passcode (if any)
    display_name: "MyApp-Bot",         # bot display name in meeting
    callback: self()                   # PID to receive events
  ]
])

# 2. Receive events directly in your process
receive do
  {:zoom_gate, {:bot_joined, _}} ->
    IO.puts("Bot joined!")

  {:zoom_gate, {:waiting_room_join, %{zoom_user_id: uid, display_name: name}}} ->
    # Your business logic decides who to admit
    :rpc.call(:"zoom_gate@10.0.1.10", ZoomGate, :admit, ["123456789", uid])
end

# 3. Or subscribe via PubSub from any process
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:123456789")
```

The consumer app is responsible for credential management:

```
Your App (GsNet, etc.)              ZoomGate
──────────────────────              ─────────────────
Stores per-account:                  Receives as opts:
  client_id (= sdk_key)               opts[:sdk_key]
  client_secret (= sdk_secret)        opts[:sdk_secret]
  refresh_token                        opts[:zak]

Before each join_meeting:            Just uses them —
  1. refresh_token → access_token    no storage, no OAuth
  2. access_token → ZAK (5 min)
  3. Pass everything to ZoomGate
```

## Zoom Setup

ZoomGate needs credentials from a Zoom Marketplace app. Here's how to get them:

### 1. Create a Zoom App

1. Go to [Zoom Marketplace](https://marketplace.zoom.us/) → **Develop** → **Build App**
2. Choose **General App** (not Meeting SDK add-on)
3. Enable **Meeting SDK** in the app's Features tab
4. Note your **Client ID** (= SDK Key) and **Client Secret** (= SDK Secret)

### 2. Set OAuth Scopes

In your app's **Scopes** tab, add:
- `user:read:zak` — needed to get ZAK tokens for host join
- `meeting:write:meeting` — needed to create meetings (optional)
- `meeting:read:meeting` — needed to read meeting info (optional)

### 3. Authorize & Get Tokens

Your consuming application (not ZoomGate) handles the OAuth flow:

```
User authorizes your Zoom app → You get refresh_token → Store it
                                                          │
When joining a meeting:                                   │
  1. refresh_token → POST zoom.us/oauth/token → access_token
  2. access_token  → GET api.zoom.us/v2/users/me/zak → ZAK
  3. Pass sdk_key + sdk_secret + zak to ZoomGate
```

### 4. Pass Credentials to ZoomGate

Credentials are passed **per request** — ZoomGate does not store them:

```bash
curl -X POST http://localhost:4000/api/sessions \
  -H "Authorization: Bearer $ZOOM_GATE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_id": "123456789",
    "sdk_key": "YOUR_CLIENT_ID",
    "sdk_secret": "YOUR_CLIENT_SECRET",
    "zak": "FRESH_ZAK_TOKEN",
    "meeting_password": "123456"
  }'
```

| Credential | What | Who provides | Lifetime |
|------------|------|-------------|----------|
| `sdk_key` | Client ID from Zoom app | Your app config | Permanent |
| `sdk_secret` | Client Secret from Zoom app | Your app config | Permanent |
| `zak` | Zoom Access Key | Your app fetches via OAuth | ~5 minutes |
| `meeting_password` | Meeting passcode | Meeting creator | Per meeting |

> **Without ZAK**: Bot joins as participant (limited permissions).
> **With ZAK**: Bot joins as host (can admit, mute, end meeting).

## Requirements

- Elixir 1.18+

## Resource Usage

| | Per Bot | 100 Bots | 500 Bots |
|---|---|---|---|
| RAM | ~2MB | ~200MB | ~1GB |
| Image | 223MB | — | — |
| Start time | <1s | — | — |

## Acknowledgements

ZoomGate's RWG (Real-time Web Gateway) WebSocket protocol implementation was inspired by
[Zoomer](https://github.com/nicksherron/zoomer), a Go-based Zoom meeting bot that pioneered
the reverse-engineering of Zoom's `as_type=1` plaintext JSON WebSocket protocol.

ZoomGate extends this work with:
- **Binary framing support** (`as_type=2`) matching the Web SDK's native wire format
- **Waiting room protocol** — full admit/deny flow verified via live WebSocket capture
- **OTP supervision** — per-meeting GenServer with automatic reconnection
- **Three API layers** — BEAM cluster, WebSocket, REST

## License

MIT
