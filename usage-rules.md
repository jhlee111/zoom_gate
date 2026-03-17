# ZoomGate Usage Rules

ZoomGate is a pure Elixir Zoom Meeting SDK bridge for waiting room access control.
It connects directly to Zoom's RWG (Real-time Web Gateway) WebSocket servers.
No C++ SDK, browser, or Puppeteer required.

## Prerequisites

- **Zoom Marketplace App** with Meeting SDK credentials (SDK Key + Secret)
- **ZAK Token** required for host-level access (waiting room management). Obtain via Zoom OAuth `GET /v2/users/me/zak`. Expires hourly — refresh before each session.
- **Waiting Room** must be enabled in meeting settings

## Critical Constraints

- **Host or Co-Host required**: Only host/co-host receives waiting room participant events. Regular participants never see `bHold: true` entries.
- **Participant ID changes on admit**: When admitted from waiting room, the `zoom_user_id` changes. Use `strConfUserID` or `userGUID` for identity continuity.
- **Display names are base64url-encoded**: Decode with `Base.url_decode64(dn2, padding: false)`.
- **ZAK required for role=1 join**: Without ZAK, host join fails with `JOIN_MEETING_FAILED`.

## API Usage

### Join a meeting

```elixir
ZoomGate.join_meeting("123456789",
  sdk_key: "...",
  sdk_secret: "...",
  zak: "eyJ0eXAi...",     # required for host/waiting room
  meeting_password: "1234", # optional
  display_name: "MyBot",    # optional
  as_type: 1,               # 1=plaintext (default), 2=binary framing
  callback: self()           # receive {:zoom_gate, {event, payload}}
)
```

### Waiting room management

```elixir
# Admit a participant
ZoomGate.admit(meeting_id, zoom_user_id)

# Deny (expel from waiting room)
ZoomGate.deny(meeting_id, zoom_user_id)

# Admit all waiting room participants
ZoomGate.admit_all(meeting_id)

# Send chat to waiting room (destNodeID=4)
ZoomGate.chat_waiting_room(meeting_id, "Please wait...")
```

### Participant management

```elixir
ZoomGate.rename(meeting_id, zoom_user_id, "New Name")
ZoomGate.expel(meeting_id, zoom_user_id)
ZoomGate.mute(meeting_id, zoom_user_id)
ZoomGate.send_chat(meeting_id, "Hello", to: zoom_user_id)
```

### Meeting lifecycle

```elixir
ZoomGate.end_meeting(meeting_id)
ZoomGate.leave_meeting(meeting_id)
ZoomGate.list_sessions()
```

### Event handling

Subscribe via callback, PubSub, or direct subscription:

```elixir
# Callback pattern
receive do
  {:zoom_gate, {:waiting_room_join, %{zoom_user_id: uid, display_name: name}}} ->
    ZoomGate.admit(meeting_id, uid)

  {:zoom_gate, {:participant_joined, %{zoom_user_id: uid, display_name: name}}} ->
    Logger.info("#{name} joined")

  {:zoom_gate, {:meeting_ended, %{reason: reason}}} ->
    Logger.info("Meeting ended: #{reason}")
end
```

Events: `:bot_joined`, `:waiting_room_join`, `:waiting_room_leave`, `:participant_joined`, `:participant_left`, `:participant_renamed`, `:chat_received`, `:host_changed`, `:meeting_ended`, `:error`.

### PubSub subscription

```elixir
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{meeting_id}")
```

### Direct subscription

```elixir
ZoomGate.Session.subscribe(meeting_id)
# Receives {:zoom_gate, {event_type, payload}} messages
```

## Configuration

```elixir
# config/runtime.exs
config :zoom_gate,
  zoom_sdk_key: System.get_env("ZOOM_SDK_KEY"),
  zoom_sdk_secret: System.get_env("ZOOM_SDK_SECRET"),
  zoom_zak: System.get_env("ZOOM_ZAK"),
  api_key: System.get_env("ZOOM_GATE_API_KEY")
```

When `sdk_key`/`sdk_secret`/`zak` are set in config, they don't need to be passed to `join_meeting/2`.

## REST API

All endpoints are under `/api/v1` and require Bearer token auth.

```
POST   /sessions                          {meeting_id, sdk_key, sdk_secret, ...}
GET    /sessions
GET    /sessions/:meeting_id
DELETE /sessions/:meeting_id
GET    /sessions/:meeting_id/participants
GET    /sessions/:meeting_id/waiting_room
POST   /sessions/:meeting_id/admit        {zoom_user_id}
POST   /sessions/:meeting_id/deny         {zoom_user_id}
POST   /sessions/:meeting_id/admit_all
POST   /sessions/:meeting_id/chat         {message, to?}
POST   /sessions/:meeting_id/chat_waiting_room  {message}
POST   /sessions/:meeting_id/rename       {zoom_user_id, display_name}
POST   /sessions/:meeting_id/expel        {zoom_user_id}
POST   /sessions/:meeting_id/mute         {zoom_user_id}
POST   /sessions/:meeting_id/end_meeting
```

## WebSocket Channel

Connect to `ws://host:4000/ws/gate` and join `gate:<meeting_id>`.

Commands: `admit`, `deny`, `admit_all`, `rename`, `expel`, `chat`, `chat_waiting_room`, `mute`, `end_meeting`, `get_status`, `get_participants`, `get_waiting_room`.

Events pushed: `waiting_room_join`, `waiting_room_leave`, `participant_joined`, `participant_left`, `chat_received`, `host_changed`, `meeting_ended`.

## Architecture

Each meeting gets its own `Session` GenServer + `MeetingBot` GenServer. Session handles API routing and event delivery. MeetingBot manages the RWG WebSocket connection.

```
ZoomGate.SessionSupervisor (DynamicSupervisor)
  └── Session (GenServer) per meeting
        └── MeetingBot (GenServer)
              └── gun WebSocket → Zoom RWG
```

Process naming uses Registry (`ZoomGate.Registry`) for cross-node addressing via `{:via, Registry, {ZoomGate.Registry, meeting_id}}`.
