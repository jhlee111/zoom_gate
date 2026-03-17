defmodule ZoomGate do
  @moduledoc """
  ZoomGate — Zoom Meeting SDK bridge for waiting room access control.

  Pure Elixir WebSocket client (~10MB) connecting directly to Zoom's RWG servers.
  No C++ SDK or browser required.

  ## API Layers

  | Layer | Protocol | Target consumers |
  |-------|----------|-----------------|
  | **BEAM Cluster** | distributed Erlang | Elixir/Erlang apps (zero overhead) |
  | **WebSocket** | Phoenix Channel | Node.js, Python, Go, browsers |
  | **REST + Webhooks** | HTTP | Any language/framework |

  ## Core Capabilities

  - **Waiting room control** — admit, deny, rename, expel participants
  - **Participant management** — list, monitor join/leave events
  - **In-meeting chat** — send messages to participants
  - **Meeting lifecycle** — join, monitor start/end, end meeting

  ## BEAM Cluster Usage

      ZoomGate.join_meeting("123456789", sdk_key: "...", sdk_secret: "...")
      ZoomGate.admit("123456789", zoom_user_id)
      ZoomGate.deny("123456789", zoom_user_id)
      ZoomGate.rename("123456789", zoom_user_id, "New Name")
      ZoomGate.admit_all("123456789")
      ZoomGate.mute("123456789", zoom_user_id)
      ZoomGate.end_meeting("123456789")
  """

  @doc """
  Starts a bot session for a Zoom meeting.

  ## Options

    * `:sdk_key` - Zoom Meeting SDK key (required)
    * `:sdk_secret` - Zoom Meeting SDK secret (required)
    * `:meeting_password` - Meeting password (optional)
    * `:display_name` - Bot display name (default: "ZoomGate-Bot")
    * `:callback` - PID or `{module, function}` for event delivery (BEAM only)
    * `:webhook_url` - URL for event delivery (REST consumers)
  """
  defdelegate join_meeting(meeting_id, opts), to: ZoomGate.SessionSupervisor

  @doc "Admits a participant from the waiting room into the meeting."
  defdelegate admit(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc "Denies a participant and removes them from the waiting room."
  defdelegate deny(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc "Renames a participant in the meeting."
  defdelegate rename(meeting_id, zoom_user_id, display_name), to: ZoomGate.Session

  @doc "Removes a participant from the meeting entirely."
  defdelegate expel(meeting_id, zoom_user_id), to: ZoomGate.Session

  @doc """
  Sends a chat message in the meeting.

  ## Options

    * `:to` - Specific zoom_user_id for private message (optional, default: all)
  """
  defdelegate send_chat(meeting_id, message, opts \\ []), to: ZoomGate.Session

  @doc "Sends a chat message to all participants (no WR-specific targeting via RWG)."
  defdelegate chat_waiting_room(meeting_id, message), to: ZoomGate.Session

  @doc "Admits all participants from the waiting room."
  defdelegate admit_all(meeting_id), to: ZoomGate.Session

  @doc "Mutes a participant."
  defdelegate mute(meeting_id, zoom_user_id), to: ZoomGate.Session

  @doc "Ends the meeting for all participants."
  defdelegate end_meeting(meeting_id), to: ZoomGate.Session

  @doc "Stops the bot and leaves the meeting."
  defdelegate leave_meeting(meeting_id), to: ZoomGate.SessionSupervisor

  @doc "Lists all active bot sessions."
  defdelegate list_sessions(), to: ZoomGate.SessionSupervisor
end
