defmodule ZoomGate do
  @moduledoc """
  ZoomGate — Zoom Meeting SDK bridge for waiting room access control.

  Wraps the Zoom Native Meeting SDK (C++ on Linux) as an Elixir/OTP service,
  exposing meeting bot capabilities through three API layers:

  ## API Layers

  | Layer | Protocol | Target consumers |
  |-------|----------|-----------------|
  | **BEAM Cluster** | distributed Erlang | Elixir/Erlang apps (zero overhead) |
  | **WebSocket** | Phoenix Channel | Node.js, Python, Go, browsers |
  | **REST + Webhooks** | HTTP | Any language/framework |

  ## Core Capabilities

  - **Waiting room control** — admit, deny, rename, expel participants
  - **Participant management** — list, monitor join/leave events
  - **In-meeting chat** — send messages to participants or waiting room
  - **Meeting lifecycle** — join as host/co-host, monitor start/end

  ## Architecture

      ┌─────────────────────────────────┐
      │  ZoomGate (Elixir/OTP)          │
      │  ├── SessionSupervisor          │  DynamicSupervisor
      │  │   └── Session (GenServer)    │  1 per active meeting
      │  │       └── Port → C++ worker  │  Zoom Native SDK
      │  ├── API Layer                  │
      │  │   ├── BEAM (GenServer.call)  │
      │  │   ├── WebSocket (Channel)    │
      │  │   └── REST + Webhooks        │
      │  └── Registry                   │  Meeting ID → Session PID
      └─────────────────────────────────┘

  ## BEAM Cluster Usage (Elixir consumers)

      # From another node in the cluster:
      ZoomGate.join_meeting("123456789", sdk_credentials)
      ZoomGate.admit("123456789", zoom_user_id, display_name: "홍길동")
      ZoomGate.deny("123456789", zoom_user_id, message: "Not authorized")

  ## Docker Deployment

      docker run -d \\
        -e ZOOM_SDK_KEY=... \\
        -e ZOOM_SDK_SECRET=... \\
        -p 4000:4000 \\
        zoomgate/zoomgate:latest
  """

  @doc """
  Starts a bot session for a Zoom meeting.

  The bot joins the meeting as host/co-host and begins monitoring
  the waiting room for participant events.

  ## Options

    * `:sdk_key` - Zoom Meeting SDK key (required)
    * `:sdk_secret` - Zoom Meeting SDK secret (required)
    * `:meeting_password` - Meeting password (optional)
    * `:join_as` - `:host` or `:co_host` (default: `:host`)
    * `:callback` - PID or `{module, function}` for event delivery (BEAM only)
    * `:webhook_url` - URL for event delivery (REST consumers)

  ## Events delivered to callback/webhook

    * `{:waiting_room_join, %{zoom_user_id: id, display_name: name}}`
    * `{:participant_joined, %{zoom_user_id: id, display_name: name}}`
    * `{:participant_left, %{zoom_user_id: id}}`
    * `{:meeting_ended, %{}}`
  """
  defdelegate join_meeting(meeting_id, opts), to: ZoomGate.SessionSupervisor

  @doc """
  Admits a participant from the waiting room into the meeting.

  ## Options

    * `:display_name` - Rename the participant upon admission (optional)
  """
  defdelegate admit(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc """
  Denies a participant and removes them from the waiting room.

  ## Options

    * `:message` - Chat message sent before removal (optional)
  """
  defdelegate deny(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc """
  Renames a participant in the meeting.
  """
  defdelegate rename(meeting_id, zoom_user_id, display_name), to: ZoomGate.Session

  @doc """
  Removes a participant from the meeting entirely.
  """
  defdelegate expel(meeting_id, zoom_user_id), to: ZoomGate.Session

  @doc """
  Sends a chat message in the meeting.

  ## Options

    * `:to` - Specific zoom_user_id for private message (optional, default: all)
  """
  defdelegate send_chat(meeting_id, message, opts \\ []), to: ZoomGate.Session

  @doc """
  Stops the bot and leaves the meeting.
  """
  defdelegate leave_meeting(meeting_id), to: ZoomGate.SessionSupervisor

  @doc """
  Lists all active bot sessions.
  """
  defdelegate list_sessions(), to: ZoomGate.SessionSupervisor
end
