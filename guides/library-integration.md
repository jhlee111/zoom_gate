# Library Integration (Embedded Mode)

ZoomGate can run as an embedded Mix dependency inside your Elixir application,
without a separate Docker container or HTTP server.

## Standalone vs Embedded

| | Standalone (Docker) | Embedded (Library) |
|---|---|---|
| **Deployment** | Separate container | Inside your app |
| **API** | REST, WebSocket, BEAM | BEAM only |
| **Endpoint** | Starts HTTP on port 4000 | Disabled |
| **Use case** | Multi-language consumers | Elixir-only consumers |
| **Overhead** | Separate process + networking | In-process, zero serialization |

## Setup

### 1. Add Dependency

```elixir
# mix.exs
defp deps do
  [
    {:zoom_gate, "~> 0.3"}
  ]
end
```

### 2. Disable the Endpoint

Add to your `config/config.exs` (or `runtime.exs`):

```elixir
config :zoom_gate, start_endpoint: false
```

This prevents ZoomGate from starting its Phoenix Endpoint, avoiding port
conflicts with your own HTTP server.

### 3. Configure Credentials (Optional)

Credentials can be passed per-request (recommended) or set as defaults:

```elixir
# config/runtime.exs
config :zoom_gate,
  zoom_sdk_key: System.get_env("ZOOM_SDK_KEY"),
  zoom_sdk_secret: System.get_env("ZOOM_SDK_SECRET")
```

ZAK tokens should always be passed per-request since they expire hourly.

## Usage

### Join a Meeting

```elixir
{:ok, _pid} = ZoomGate.join_meeting("123456789",
  sdk_key: "YOUR_CLIENT_ID",
  sdk_secret: "YOUR_CLIENT_SECRET",
  zak: "FRESH_ZAK_TOKEN",
  callback: self()
)
```

### Receive Events

```elixir
# Option 1: Callback PID (direct message delivery)
receive do
  {:zoom_gate, {:waiting_room_join, %{zoom_user_id: uid, display_name: name}}} ->
    ZoomGate.admit("123456789", uid)

  {:zoom_gate, {:participant_joined, participant}} ->
    Logger.info("#{participant.display_name} joined")
end

# Option 2: PubSub (works across any process in your app)
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:123456789")
```

### Available Commands

```elixir
# Session lifecycle
ZoomGate.join_meeting(meeting_id, opts)
ZoomGate.leave_meeting(meeting_id)
ZoomGate.list_sessions()

# Waiting room
ZoomGate.admit(meeting_id, zoom_user_id)
ZoomGate.deny(meeting_id, zoom_user_id)
ZoomGate.admit_all(meeting_id)

# Participant management
ZoomGate.rename(meeting_id, zoom_user_id, "New Name")
ZoomGate.expel(meeting_id, zoom_user_id)
ZoomGate.mute(meeting_id, zoom_user_id)
ZoomGate.spotlight(meeting_id, zoom_user_id)

# Chat
ZoomGate.send_chat(meeting_id, "Hello", to: zoom_user_id)
ZoomGate.chat_waiting_room(meeting_id, "Please wait...")

# Meeting control
ZoomGate.start_recording(meeting_id)
ZoomGate.stop_recording(meeting_id)
ZoomGate.lock_sharing(meeting_id, true)
ZoomGate.end_meeting(meeting_id)
```

## What Starts in Embedded Mode

| Component | Starts? | Purpose |
|-----------|---------|---------|
| `Phoenix.PubSub` | Yes | Event delivery across processes |
| `Registry` | Yes | Session lookup by meeting ID |
| `SessionSupervisor` | Yes | Per-meeting bot lifecycle |
| `Endpoint` | **No** | HTTP/WS server (disabled) |
| `ClusterSupervisor` | Conditional | Only if `cluster_topologies` configured |

## PubSub Sharing

ZoomGate starts its own `Phoenix.PubSub` instance (`ZoomGate.PubSub`). If your
app already runs Phoenix.PubSub, both instances coexist — no conflict.

To subscribe to ZoomGate events from your app:

```elixir
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{meeting_id}")
```

## Example: GenServer Consumer

```elixir
defmodule MyApp.ZoomHandler do
  use GenServer

  def start_link(meeting_id) do
    GenServer.start_link(__MODULE__, meeting_id)
  end

  @impl true
  def init(meeting_id) do
    {:ok, _pid} = ZoomGate.join_meeting(meeting_id,
      sdk_key: MyApp.Config.zoom_sdk_key(),
      sdk_secret: MyApp.Config.zoom_sdk_secret(),
      zak: MyApp.Zoom.fresh_zak(),
      callback: self()
    )

    {:ok, %{meeting_id: meeting_id}}
  end

  @impl true
  def handle_info({:zoom_gate, {:waiting_room_join, participant}}, state) do
    # Your admission logic here
    if MyApp.Admission.allowed?(participant) do
      ZoomGate.admit(state.meeting_id, participant.zoom_user_id)
    else
      ZoomGate.deny(state.meeting_id, participant.zoom_user_id)
    end

    {:noreply, state}
  end

  def handle_info({:zoom_gate, {:meeting_ended, _reason}}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:zoom_gate, _event}, state) do
    {:noreply, state}
  end
end
```
