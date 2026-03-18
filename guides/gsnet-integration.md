# GsNet Integration Guide

## Overview

ZoomGate is a pure SDK proxy -- it has ZERO business logic. GsNet makes all
decisions about who can join, what their display name should be, etc. ZoomGate
just executes commands and emits events.

This guide covers the practical integration patterns between GsNet and
ZoomGate, based on live testing findings from 2026-03-17.

## Prerequisites

- ZoomGate running (standalone Docker or embedded in a BEAM cluster)
- S2S OAuth app configured in Zoom Marketplace with a webhook endpoint
- General App (Meeting SDK) credentials for bot connections
- Zoom account settings: waiting room enabled, cloud recording enabled

## Architecture

```
GsNet (Business Logic)
  |-- AdmissionHandler -- receives webhook + RWG events, decides admit/deny
  |-- BridgeClient     -- calls ZoomGate GenServers via Erlang distribution
  |-- ZoomAccount      -- Ash resource, stores member's Zoom registrant_id
  '-- ZoomMeeting      -- Ash resource, tracks active meetings

ZoomGate (SDK Proxy)
  |-- Session          -- per-meeting GenServer
  |-- MeetingBot       -- RWG WebSocket connection to Zoom
  |-- WebhookRouter    -- receives Zoom S2S webhooks
  '-- ZoomAPI          -- REST API client (create meetings, get ZAK, etc.)
```

### Responsibility Boundary

| Concern | Owner | Notes |
|---------|-------|-------|
| Who gets admitted | GsNet | Member lookup, authorization (ash_grant) |
| What display name to use | GsNet | Format: "이름 (센터)" |
| When to start recording | GsNet | Based on class schedule |
| Executing SDK commands | ZoomGate | admit, rename, record, etc. |
| Event delivery | ZoomGate | RWG events + webhook forwarding |
| Credential management | GsNet | OAuth tokens, ZAK refresh |

## Connection Methods

### 1. BEAM Cluster (Recommended)

The preferred integration for GsNet. Both applications run in the same
Erlang cluster via `libcluster`, so calls are direct function invocations
with no serialization overhead.

```elixir
# GsNet calls ZoomGate directly via Erlang distribution
ZoomGate.admit(meeting_id, zoom_user_id)
ZoomGate.rename(meeting_id, zoom_user_id, "홍길동 (강남센터)")
ZoomGate.start_recording(meeting_id)
ZoomGate.lock_sharing(meeting_id, true)
ZoomGate.spotlight(meeting_id, zoom_user_id)
```

Cluster configuration (in both apps):

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    local: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"zoom_gate@127.0.0.1", :"gs_net@127.0.0.1"]]
    ]
  ]
```

### 2. REST API

For non-Elixir consumers or when running ZoomGate as a standalone service.

```bash
# Waiting room commands
POST /api/sessions/:meeting_id/admit           {"zoom_user_id": 123}
POST /api/sessions/:meeting_id/deny            {"zoom_user_id": 123}
POST /api/sessions/:meeting_id/admit_all       {}
POST /api/sessions/:meeting_id/rename          {"zoom_user_id": 123, "display_name": "..."}
POST /api/sessions/:meeting_id/expel           {"zoom_user_id": 123}

# Chat
POST /api/sessions/:meeting_id/chat            {"message": "Hello", "to": 123}
POST /api/sessions/:meeting_id/chat_waiting_room {"message": "Please wait..."}

# Meeting control
POST /api/sessions/:meeting_id/mute            {"zoom_user_id": 123}
POST /api/sessions/:meeting_id/start_recording {}
POST /api/sessions/:meeting_id/stop_recording  {}
POST /api/sessions/:meeting_id/lock_sharing    {"locked": true}
POST /api/sessions/:meeting_id/spotlight       {"zoom_user_id": 123, "spotlight": true}
POST /api/sessions/:meeting_id/end_meeting     {}
```

All endpoints require `Authorization: Bearer <api_key>` when `ZOOM_GATE_API_KEY`
is configured.

### 3. WebSocket Channel

For real-time bidirectional communication via Phoenix Channels.

```javascript
const socket = new Socket("ws://host:4000/ws/gate", {
  params: { api_key: "YOUR_API_KEY" }
})
socket.connect()

const channel = socket.channel(`zoom_gate:${meetingId}`)
channel.join()

// Send commands
channel.push("admit", {zoom_user_id: 123})
channel.push("rename", {zoom_user_id: 123, display_name: "New Name"})
channel.push("start_recording", {})
channel.push("stop_recording", {})
channel.push("lock_sharing", {locked: true})
channel.push("spotlight", {zoom_user_id: 123})

// Receive events
channel.on("waiting_room_join", (data) => { /* ... */ })
channel.on("participant_joined", (data) => { /* ... */ })
channel.on("meeting_ended", (data) => { /* ... */ })
```

## Waiting Room Flow (Core Use Case)

This is the primary integration pattern for GsNet's class management system.

### Step-by-step

1. **Meeting created** -- GsNet calls `ZoomGate.ZoomAPI.create_meeting/2` with
   the S2S OAuth token to create a scheduled meeting.

2. **Bot joins** -- GsNet calls `ZoomGate.join_meeting/2` which starts a Session
   and connects a MeetingBot to the meeting via RWG WebSocket.

3. **User enters waiting room** -- Two events fire simultaneously:
   - **Webhook** (1-5s latency): `meeting.participant_joined_waiting_room` with
     `email`, `registrant_id`, `user_id`
   - **RWG** (50-200ms latency): `waiting_room_join` with `zoom_user_id`,
     `display_name`, `strConfUserID`

4. **GsNet identifies user**:
   - Use `registrant_id` from webhook (same as `strConfUserID` from RWG)
   - Look up the member in GsNet's database by their stored `registrant_id`
   - Check membership and authorization for this class/session via ash_grant

5. **Admit or deny**:
   - **Authorized**: `ZoomGate.admit(meeting_id, zoom_user_id)`
   - **Not authorized**: `ZoomGate.deny(meeting_id, zoom_user_id)`
   - **Not logged in** (no `registrant_id`): Send a chat message prompting the
     user to log in to their Zoom account

6. **User ID changes after admit** -- this is critical:
   - After admit, the old `zoom_user_id` is **invalidated**
   - Watch for the `participant_joined` event with a new `zoom_user_id` but the
     same `registrant_id` / `strConfUserID`
   - Use the **NEW** `zoom_user_id` for rename and all subsequent commands

7. **Rename with business context**:
   - `ZoomGate.rename(meeting_id, new_zoom_user_id, "홍길동 (강남센터)")`
   - Must use the new ID from step 6, not the old waiting room ID

8. **User leaves** -- `participant_left` event fires for attendance tracking

### Sequence Diagram

```
GsNet                    ZoomGate                   Zoom Cloud
  |                         |                           |
  |-- join_meeting -------->|                           |
  |                         |-- RWG WebSocket --------->|
  |<-- :bot_joined ---------|                           |
  |                         |                           |
  |                         |    User enters WR         |
  |                         |<-- evt=7937 add(bHold) ---|
  |<-- :waiting_room_join --|                           |
  |                         |                           |
  |  (webhook arrives)      |                           |
  |<-- registrant_id, email-|                           |
  |                         |                           |
  |  Look up member         |                           |
  |  Check authorization    |                           |
  |                         |                           |
  |-- admit(old_id) ------->|-- evt=4113 putOnHold ---->|
  |                         |<-- evt=7937 remove(old) --|
  |                         |<-- evt=7937 add(new) -----|
  |<-- :participant_joined -|  (NEW zoom_user_id)       |
  |                         |                           |
  |-- rename(new_id, name)->|-- evt=4109 rename ------->|
  |                         |<-- evt=7937 update(dn2) --|
```

## ID Mapping Reference

Zoom uses multiple identifiers across webhook and RWG systems. Correct mapping
is essential for correlating identity data with real-time state.

| Source | Field | Stable? | Use for |
|--------|-------|---------|---------|
| Webhook | `registrant_id` | Yes (per account) | Primary member lookup key |
| Webhook | `email` | Mostly (can change) | Display only, not for lookup |
| Webhook | `participant_uuid` | No (per session) | Not recommended |
| Webhook | `user_id` | No (changes on admit) | Command targeting (before admit only) |
| RWG | `strConfUserID` | Yes (same as registrant_id) | In-session member lookup |
| RWG | `userGUID` | No (per session) | Fallback correlation for guests |
| RWG | participant `id` | No (ephemeral) | Command targeting (current session) |
| RWG | `sdkKey` | Yes | Bot vs. real user distinction |

### Correlation Strategy

```
Webhook arrives: {email, registrant_id, participant_uuid}
       |
       v
Match to RWG roster: registrant_id == strConfUserID
       |
       v
Result: plaintext email + real-time roster state (bHold, muted, etc.)
```

If `registrant_id` is absent (guest without Zoom account), fall back to
`participant_uuid == userGUID`.

### Bot vs. Real User

SDK bot clients include a `sdkKey` field in their roster entry. Real users
do not. This is the most reliable way to filter out the bot from participant
lists:

```elixir
real_participants =
  Enum.reject(participants, fn p -> Map.has_key?(p, :sdk_key) end)
```

## Subscribing to Events

### From GsNet (BEAM Cluster)

```elixir
# In GsNet's AdmissionHandler
Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{meeting_id}")

# Receive ZoomGate events
def handle_info({:zoom_gate, {:waiting_room_join, participant}}, state) do
  # participant.zoom_user_id, participant.display_name
  # Webhook will arrive shortly with registrant_id for member lookup
  {:noreply, state}
end

def handle_info({:zoom_gate, {:participant_joined, participant}}, state) do
  # participant.zoom_user_id is the NEW ID after admit
  # Use this ID for rename and subsequent commands
  {:noreply, state}
end

def handle_info({:zoom_gate, {:meeting_ended, reason}}, state) do
  # Clean up, record attendance
  {:noreply, state}
end
```

### Webhook Events from Zoom S2S

GsNet should also handle Zoom S2S webhooks directly for identity data:

```elixir
def handle_info({:zoom_webhook, :participant_waiting, participant}, state) do
  # participant.registrant_id -- use for member lookup
  # participant.email -- plaintext email
  member = MyApp.Members.find_by_registrant_id(participant.registrant_id)

  case member do
    nil ->
      # Unknown user, deny or send chat message
      ZoomGate.send_chat(state.meeting_id, "Please log in to join")

    member ->
      if authorized?(member, state.class_id) do
        ZoomGate.admit(state.meeting_id, participant.user_id)
      else
        ZoomGate.deny(state.meeting_id, participant.user_id)
      end
  end

  {:noreply, state}
end

def handle_info({:zoom_webhook, :participant_joined, participant}, state) do
  # participant.user_id is the NEW ID after admit
  # Now rename with business display name
  member = MyApp.Members.find_by_registrant_id(participant.registrant_id)

  if member do
    display_name = "#{member.name} (#{member.center_name})"
    ZoomGate.rename(state.meeting_id, participant.user_id, display_name)
  end

  {:noreply, state}
end
```

## Available Commands

### Waiting Room

| Function | REST Endpoint | Description |
|----------|--------------|-------------|
| `ZoomGate.admit(meeting_id, zoom_user_id)` | `POST .../admit` | Admit from waiting room |
| `ZoomGate.deny(meeting_id, zoom_user_id)` | `POST .../deny` | Deny and remove |
| `ZoomGate.admit_all(meeting_id)` | `POST .../admit_all` | Admit all waiting |

### Participant Management

| Function | REST Endpoint | Description |
|----------|--------------|-------------|
| `ZoomGate.rename(meeting_id, zoom_user_id, name)` | `POST .../rename` | Change display name |
| `ZoomGate.expel(meeting_id, zoom_user_id)` | `POST .../expel` | Remove from meeting |
| `ZoomGate.mute(meeting_id, zoom_user_id)` | `POST .../mute` | Mute participant |
| `ZoomGate.spotlight(meeting_id, zoom_user_id)` | `POST .../spotlight` | Spotlight video |

### Meeting Control

| Function | REST Endpoint | Description |
|----------|--------------|-------------|
| `ZoomGate.start_recording(meeting_id)` | `POST .../start_recording` | Start cloud recording |
| `ZoomGate.stop_recording(meeting_id)` | `POST .../stop_recording` | Stop cloud recording |
| `ZoomGate.lock_sharing(meeting_id, locked)` | `POST .../lock_sharing` | Lock/unlock screen sharing |
| `ZoomGate.send_chat(meeting_id, message)` | `POST .../chat` | Send chat message |
| `ZoomGate.chat_waiting_room(meeting_id, msg)` | `POST .../chat_waiting_room` | Chat to waiting room |
| `ZoomGate.end_meeting(meeting_id)` | `POST .../end_meeting` | End meeting for all |

### Session Lifecycle

| Function | REST Endpoint | Description |
|----------|--------------|-------------|
| `ZoomGate.join_meeting(meeting_id, opts)` | `POST /api/sessions` | Start bot session |
| `ZoomGate.leave_meeting(meeting_id)` | `DELETE /api/sessions/:id` | Stop bot session |
| `ZoomGate.list_sessions()` | `GET /api/sessions` | List active sessions |
| `ZoomGate.Session.get_status(meeting_id)` | `GET /api/sessions/:id` | Get session status |

### REST API (Zoom S2S OAuth)

| Function | Description |
|----------|-------------|
| `ZoomGate.ZoomAPI.get_access_token()` | Get S2S OAuth token |
| `ZoomGate.ZoomAPI.create_meeting(token, opts)` | Create a meeting |
| `ZoomGate.ZoomAPI.delete_meeting(token, id)` | Delete a meeting |
| `ZoomGate.ZoomAPI.get_zak(token)` | Get ZAK token for host join |
| `ZoomGate.ZoomAPI.update_account_settings(token, settings)` | Update account settings |

## Recording Lifecycle

Cloud recording follows a state machine tracked via `cmrServerStatus` in
meeting settings events:

```
start_recording/1
  --> bRecord: true
  --> cmrServerStatus: 1  (initializing)
  --> cmrServerStatus: 2  (recording active)
  ... recording ...
stop_recording/1
  --> cmrServerStatus: 4  (stopping)
  --> bRecord: false
```

GsNet should track `cmrServerStatus` to confirm recording is active before
relying on it (e.g., do not show "Recording" indicator until status reaches 2).

## Screen Sharing Control

Lock screen sharing to prevent participants from sharing without permission:

```elixir
# Lock sharing (only host can share)
ZoomGate.lock_sharing(meeting_id, true)

# Unlock sharing (participants can share)
ZoomGate.lock_sharing(meeting_id, false)
```

The lock state is confirmed via a `meetingSettings` event (evt 7938) with
the updated `lockShare` value.

## Spotlight

Spotlight a participant's video to pin it as the primary view for all
attendees:

```elixir
# Spotlight on
ZoomGate.spotlight(meeting_id, zoom_user_id)

# Spotlight off (pass false as third argument via Session)
ZoomGate.Session.spotlight(meeting_id, zoom_user_id, false)
```

## Troubleshooting

### Error 3099: Meeting Registration Required

**Symptom**: Join fails with result code 3099.

**Cause**: The meeting has registration enabled, and the SDK client is joining
as an attendee (role=0).

**Fix**: Use `role: 1` for SDK bots. SDK bots joining as host bypass
registration requirements. Ensure a valid ZAK token is provided -- without it,
the bot defaults to role=0.

### Error 3000: Only One Active Meeting Per Account

**Symptom**: Join fails with "only one active meeting" error.

**Cause**: The Zoom account already has an active meeting session from a
previous bot that did not leave cleanly.

**Fix**: Send a leave command on the old session before joining a new one.
Implement graceful shutdown in the bot lifecycle to always leave on termination.

### Admit Changes zoom_user_id

**Symptom**: After admitting a participant, `rename` or other commands sent to
their old ID fail silently.

**Cause**: The admit process removes the old participant entry and creates a new
one with a different `id`. This is standard Zoom behavior.

**Fix**: After detecting the admit sequence, re-map the participant using
`strConfUserID` (stable across the transition) or `registrant_id` from the
webhook. Never cache `zoom_user_id` values across admit boundaries.

### putOnHold(false) Unreliable for Individual Admits

**Symptom**: Sending admit for a specific user sometimes does not work.

**Cause**: Timing issues or stale participant IDs.

**Fix**: Use `admit_all` as a more reliable alternative when admitting
individual users fails. If selective admission is required, retry after
confirming the participant's current ID from the latest roster event.

### Chat Encryption

**Symptom**: Chat messages from real users arrive encrypted and unreadable.

**Cause**: Real user chat is E2E encrypted. Only waiting room chat
(destNodeID=4) uses plain base64 encoding.

**Fix**: For GsNet's use case (sending instructions to waiting room users),
use `chat_waiting_room/2` which targets destNodeID=4 and is readable. Chat
from real users in the meeting requires the meeting's encryption key to decrypt.

### Commands Silently Ignored

**Symptom**: A command returns `:ok` but has no effect.

**Cause**: Most commands that target a specific `zoom_user_id` do not return
errors from Zoom. If the user has already left or the ID is stale, the command
is silently ignored.

**Fix**: Track participant state via events. Before sending a command, verify
the participant is still present with a valid ID. Use `Session.get_status/1`
to check the current participant roster.

### ZAK Token Expired

**Symptom**: `join_meeting/2` fails with `JOIN_MEETING_FAILED` (error 200).

**Cause**: The ZAK token has expired (lifetime is approximately 1 hour).

**Fix**: Always refresh the ZAK token via `ZoomGate.ZoomAPI.get_zak/1`
immediately before each `join_meeting/2` call. Do not cache ZAK tokens.

### Breakout Rooms Not Available

**Symptom**: Breakout room commands fail or have no effect.

**Cause**: Breakout rooms must be enabled at the Zoom account level, not just
the meeting level. The setting only takes effect for meetings created after
the change.

**Fix**:
1. Enable breakout rooms in Zoom account settings (admin panel).
2. Create a new meeting after enabling the setting.
3. The SDK bot must be host or co-host to manage breakout rooms.

## GsNet Module Reference

These are the GsNet modules that interact with ZoomGate:

| Module | Purpose |
|--------|---------|
| `GsNet.Integrations.Zoom.BridgeClient` | Calls ZoomGate GenServers via Erlang distribution |
| `GsNet.Integrations.Zoom.AdmissionHandler` | Handles waiting room events, decides admit/deny |
| `GsNet.Integrations.Zoom.ZoomAccount` | Ash resource storing member's Zoom `registrant_id` |
| `GsNet.Integrations.Zoom.ZoomMeeting` | Ash resource tracking active meetings |

## Example: Full Admission Flow in GsNet

```elixir
defmodule GsNet.Integrations.Zoom.AdmissionHandler do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    meeting_id = opts[:meeting_id]
    class_id = opts[:class_id]

    # Subscribe to ZoomGate events
    Phoenix.PubSub.subscribe(ZoomGate.PubSub, "zoom_gate:#{meeting_id}")

    # Start bot session
    {:ok, _pid} = ZoomGate.join_meeting(meeting_id,
      sdk_key: config(:sdk_key),
      sdk_secret: config(:sdk_secret),
      zak: GsNet.Integrations.Zoom.fresh_zak(),
      callback: self()
    )

    {:ok, %{
      meeting_id: meeting_id,
      class_id: class_id,
      pending_admits: %{},   # registrant_id => member
      id_map: %{}            # old_zoom_user_id => registrant_id
    }}
  end

  @impl true
  def handle_info({:zoom_gate, {:bot_joined, _}}, state) do
    # Bot is ready, enable waiting room features
    ZoomGate.lock_sharing(state.meeting_id, true)
    {:noreply, state}
  end

  def handle_info({:zoom_gate, {:waiting_room_join, participant}}, state) do
    # RWG event arrives first (50-200ms), webhook follows (1-5s)
    # Store the zoom_user_id mapping for when webhook arrives
    {:noreply, state}
  end

  def handle_info({:zoom_webhook, :participant_waiting, webhook_data}, state) do
    registrant_id = webhook_data.registrant_id
    zoom_user_id = webhook_data.user_id

    case GsNet.Members.find_by_registrant_id(registrant_id) do
      nil ->
        ZoomGate.chat_waiting_room(state.meeting_id,
          "Please log in to your Zoom account to join.")
        {:noreply, state}

      member ->
        if GsNet.Authorization.allowed?(member, state.class_id) do
          ZoomGate.admit(state.meeting_id, zoom_user_id)
          pending = Map.put(state.pending_admits, registrant_id, member)
          {:noreply, %{state | pending_admits: pending}}
        else
          ZoomGate.deny(state.meeting_id, zoom_user_id)
          {:noreply, state}
        end
    end
  end

  def handle_info({:zoom_webhook, :participant_joined, webhook_data}, state) do
    registrant_id = webhook_data.registrant_id
    new_zoom_user_id = webhook_data.user_id

    case Map.pop(state.pending_admits, registrant_id) do
      {nil, _pending} ->
        {:noreply, state}

      {member, pending} ->
        # Rename with business display name using the NEW user ID
        display_name = "#{member.name} (#{member.center_name})"
        ZoomGate.rename(state.meeting_id, new_zoom_user_id, display_name)
        {:noreply, %{state | pending_admits: pending}}
    end
  end

  def handle_info({:zoom_gate, {:meeting_ended, _reason}}, state) do
    # Record attendance, clean up
    {:stop, :normal, state}
  end

  def handle_info({:zoom_gate, _event}, state) do
    {:noreply, state}
  end
end
```
