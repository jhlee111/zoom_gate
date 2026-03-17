defmodule ZoomGate do
  @moduledoc """
  ZoomGate — Zoom Meeting SDK bridge for waiting room access control.

  Pure Elixir WebSocket client connecting directly to Zoom's RWG (Real-time Web Gateway)
  servers. No C++ SDK, browser, or Puppeteer required.

  ## Prerequisites

  1. **Zoom Marketplace App** — Create a "Meeting SDK" app at [marketplace.zoom.us](https://marketplace.zoom.us)
  2. **SDK Key & Secret** — From the app's "App Credentials" page
  3. **ZAK Token** — Required for host-level access (waiting room management).
     Obtain via [Zoom OAuth](https://developers.zoom.us/docs/api/rest/reference/zoom-api/methods/#operation/userZak)
     (`GET /v2/users/me/zak`).
  4. **Waiting Room Enabled** — The meeting must have "Waiting Room" turned on in settings

  ## Important Constraints

  - **Host or Co-Host required** — Only host/co-host receives waiting room participant
    events (`bHold: true` in `evt=7937`). Regular participants never see waiting room entries.
  - **ZAK required for host join** — Joining with `role: 1` requires a valid ZAK token.
    Without ZAK, join fails with `JOIN_MEETING_FAILED` (errorCode 200).
  - **ZAK expires hourly** — ZAK tokens are valid for ~1 hour. Refresh via OAuth before each session.
  - **Participant ID changes on admit** — When a user is admitted from the waiting room,
    their `zoom_user_id` changes. Track users by `strConfUserID` or `userGUID` for continuity.
  - **Display names are base64url-encoded** — The `dn2` field uses base64url without padding.
    Use `Base.url_decode64(dn2, padding: false)` to decode.

  ## Configuration

      # config/runtime.exs
      config :zoom_gate,
        zoom_sdk_key: System.get_env("ZOOM_SDK_KEY"),
        zoom_sdk_secret: System.get_env("ZOOM_SDK_SECRET"),
        zoom_zak: System.get_env("ZOOM_ZAK"),
        api_key: System.get_env("ZOOM_GATE_API_KEY")

  ## Quick Start

      # Join a meeting as host (with waiting room monitoring)
      ZoomGate.join_meeting("123456789",
        sdk_key: "YOUR_SDK_KEY...",
        sdk_secret: "abc123...",
        zak: "eyJ0eXAi...",
        callback: self()
      )

      # Receive events
      receive do
        {:zoom_gate, {:waiting_room_join, %{zoom_user_id: uid, display_name: name}}} ->
          IO.puts("\#{name} entered waiting room")
          ZoomGate.admit("123456789", uid)

        {:zoom_gate, {:participant_joined, participant}} ->
          IO.puts("\#{participant.display_name} joined meeting")
      end

  ## API Layers

  | Layer | Protocol | Target consumers |
  |-------|----------|-----------------|
  | **BEAM Cluster** | distributed Erlang | Elixir/Erlang apps (zero overhead) |
  | **WebSocket** | Phoenix Channel | Node.js, Python, Go, browsers |
  | **REST + Webhooks** | HTTP | Any language/framework |

  ## BEAM Cluster API

      ZoomGate.join_meeting(meeting_id, opts)
      ZoomGate.admit(meeting_id, zoom_user_id)
      ZoomGate.deny(meeting_id, zoom_user_id)
      ZoomGate.admit_all(meeting_id)
      ZoomGate.rename(meeting_id, zoom_user_id, "New Name")
      ZoomGate.expel(meeting_id, zoom_user_id)
      ZoomGate.send_chat(meeting_id, "Hello", to: zoom_user_id)
      ZoomGate.chat_waiting_room(meeting_id, "Please wait...")
      ZoomGate.mute(meeting_id, zoom_user_id)
      ZoomGate.end_meeting(meeting_id)
      ZoomGate.leave_meeting(meeting_id)
      ZoomGate.list_sessions()

  ## Events

  Delivered via callback, PubSub, subscriber, or webhook:

  | Event | Payload |
  |-------|---------|
  | `:bot_joined` | `%{meeting_id}` |
  | `:waiting_room_join` | `%{zoom_user_id, display_name}` |
  | `:waiting_room_leave` | `%{zoom_user_id}` |
  | `:participant_joined` | `%{zoom_user_id, display_name, role, ...}` |
  | `:participant_left` | `%{zoom_user_id}` |
  | `:participant_renamed` | `%{zoom_user_id, old_name, new_name}` |
  | `:chat_received` | `%{from_user_id, message}` |
  | `:host_changed` | `%{new_host_id}` |
  | `:meeting_ended` | `%{reason}` |
  | `:error` | `%{message}` |

  ## Wire Format

  The bot connects to Zoom's RWG WebSocket with two supported modes:

  - `as_type: 1` — Plaintext JSON text frames (default, simpler)
  - `as_type: 2` — Binary framing with 17-byte header (matches Web SDK)

  Both modes are fully functional for waiting room management.
  See `ZoomGate.MeetingBot.Frame` for binary frame details.
  """

  @doc """
  Starts a bot session for a Zoom meeting.

  Returns `{:ok, pid}` on success, `{:error, reason}` on failure.

  ## Options

    * `:sdk_key` - Zoom Meeting SDK key (required, or set via config)
    * `:sdk_secret` - Zoom Meeting SDK secret (required, or set via config)
    * `:zak` - ZAK token for host access (required for waiting room management)
    * `:meeting_password` - Meeting password (optional)
    * `:display_name` - Bot display name (default: `"ZoomGate-Bot"`)
    * `:as_type` - Wire format: `1` for plaintext, `2` for binary (default: `1`)
    * `:callback` - PID or `{module, function}` for event delivery (BEAM only)
    * `:webhook_url` - URL for event delivery via HTTP POST (REST consumers)
  """
  defdelegate join_meeting(meeting_id, opts), to: ZoomGate.SessionSupervisor

  @doc """
  Admits a participant from the waiting room into the meeting.

  Sends `evt=4113 {id, bHold: false}` to the RWG server.
  The participant's `zoom_user_id` will change after admission.
  """
  defdelegate admit(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc """
  Denies a participant and removes them from the waiting room.

  Uses `evt=4107` (expel) — there is no separate "deny" event in the RWG protocol.
  """
  defdelegate deny(meeting_id, zoom_user_id, opts \\ []), to: ZoomGate.Session

  @doc "Renames a participant in the meeting."
  defdelegate rename(meeting_id, zoom_user_id, display_name), to: ZoomGate.Session

  @doc "Removes a participant from the meeting entirely (kick)."
  defdelegate expel(meeting_id, zoom_user_id), to: ZoomGate.Session

  @doc """
  Sends a chat message in the meeting.

  ## Options

    * `:to` - Specific `zoom_user_id` for private message (default: everyone)
  """
  defdelegate send_chat(meeting_id, message, opts \\ []), to: ZoomGate.Session

  @doc """
  Sends a chat message to all participants in the waiting room.

  Uses `destNodeID=4` (SilentModeUsers). The message is base64-encoded,
  not E2E encrypted.
  """
  defdelegate chat_waiting_room(meeting_id, message), to: ZoomGate.Session

  @doc "Admits all participants currently in the waiting room."
  defdelegate admit_all(meeting_id), to: ZoomGate.Session

  @doc "Mutes a participant's audio."
  defdelegate mute(meeting_id, zoom_user_id), to: ZoomGate.Session

  @doc "Ends the meeting for all participants."
  defdelegate end_meeting(meeting_id), to: ZoomGate.Session

  @doc "Stops the bot session and leaves the meeting."
  defdelegate leave_meeting(meeting_id), to: ZoomGate.SessionSupervisor

  @doc "Lists all active bot sessions as `[{meeting_id, pid}]`."
  defdelegate list_sessions(), to: ZoomGate.SessionSupervisor
end
