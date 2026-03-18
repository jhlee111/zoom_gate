# Protocol Analyzer

The Protocol Analyzer is an ICE (In-Circuit Emulator) for the Zoom RWG WebSocket protocol.
It records, decodes, and correlates all WebSocket traffic during a live meeting session,
enabling systematic reverse engineering of undocumented protocol areas.

## Prerequisites

Two Zoom Marketplace apps are required:

| App | Type | `.env` Keys | Purpose |
|-----|------|-------------|---------|
| General App (Meeting SDK) | User-managed | `ZOOM_SDK_KEY`, `ZOOM_SDK_SECRET` | MeetingBot JWT signing (RWG connection) |
| Server-to-Server OAuth | Admin-managed | `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET` | REST API (create meetings, get ZAK) |

All credentials are loaded from `.env` via Dotenvy at boot (see `config/runtime.exs`).

```bash
# .env
ZOOM_SDK_KEY=your-general-app-client-id
ZOOM_SDK_SECRET=your-general-app-client-secret
ZOOM_ACCOUNT_ID=your-s2s-account-id
ZOOM_CLIENT_ID=your-s2s-client-id
ZOOM_CLIENT_SECRET=your-s2s-client-secret
```

## Quick Start

Start the Phoenix app, then in `iex -S mix`:

```elixir
# 1. Create a meeting via S2S OAuth API
{:ok, token} = ZoomGate.ZoomAPI.get_access_token()
{:ok, meeting} = ZoomGate.ZoomAPI.create_meeting(token, topic: "Analyzer Session", waiting_room: true)

meeting_number = to_string(meeting.meeting_id)
session_id = "analyzer-#{meeting_number}"

# 2. Enable the Analyzer
{:ok, pids} = ZoomGate.Analyzer.enable(session_id, meeting_number: meeting_number)

# 3. Start a MeetingBot with the analyzer tap attached
sdk_key = Application.get_env(:zoom_gate, :zoom_sdk_key)
sdk_secret = Application.get_env(:zoom_gate, :zoom_sdk_secret)

{:ok, bot} = GenServer.start(ZoomGate.MeetingBot, [
  meeting_number: meeting_number,
  password: meeting.password,
  display_name: "AnalyzerBot",
  sdk_key: sdk_key,
  sdk_secret: sdk_secret,
  zak: "",
  role: 1,
  as_type: 1,
  session_pid: self(),
  analyzer: pids.tap   # <-- this connects the analyzer
])

# 4. Query the analyzer
ZoomGate.Analyzer.get_state(session_id)        # full client state
ZoomGate.Analyzer.get_participants(session_id)  # participant map
ZoomGate.Analyzer.get_records(session_id)       # all recorded messages
ZoomGate.Analyzer.get_unknowns(session_id)      # unknown events (discovery!)
ZoomGate.Analyzer.get_correlations(session_id)  # command-response pairs
ZoomGate.Analyzer.export(session_id)            # JSON-exportable data

# 5. Clean up
ZoomGate.MeetingBot.leave(bot)
ZoomGate.Analyzer.disable(session_id)
ZoomGate.ZoomAPI.delete_meeting(token, meeting.meeting_id)
```

## Architecture

```
MeetingBot ──(raw WS frames)──> Tap ──(decoded)──> StateServer
                                                    ├── ClientState (pure reducer)
                                                    ├── Recorder (ETS log)
                                                    ├── Correlator (cmd→response)
                                                    ├── :telemetry events
                                                    └── PubSub broadcast
```

- **Tap** — Receives raw `{:raw_ws, direction, data}` from MeetingBot, decodes via `EventDecoder`, forwards to StateServer.
- **StateServer** — GenServer composing all analyzer components. Maintains client state, records messages, emits telemetry.
- **ClientState** — Pure reducer: `apply_event(state, event) → {new_state, changes}`. No side effects.
- **Recorder** — ETS-based append-only log. `:ordered_set, :public` for concurrent reads.
- **Correlator** — Links outgoing commands to response events using known patterns + heuristic discovery.

## Querying Recorded Data

### All Messages

```elixir
records = ZoomGate.Analyzer.get_records("my-session")

for r <- records do
  dir = if r.direction == :incoming, do: "←", else: "→"
  name = if r.event_info, do: r.event_info.name, else: "UNKNOWN"
  IO.puts("#{dir} evt=#{r.evt} #{name}")
end
```

### Filter by Event Code or Category

```elixir
alias ZoomGate.Analyzer.Recorder

# By event code
Recorder.get_by_evt("my-session", 7937)      # all roster updates

# By category
Recorder.get_by_category("my-session", :chat) # all chat events
Recorder.get_by_category("my-session", :audio) # all audio events
```

### Unknown Events (Protocol Discovery)

```elixir
unknowns = ZoomGate.Analyzer.get_unknowns("my-session")

for u <- unknowns do
  IO.puts("evt=#{u.evt} body=#{inspect(u.body)}")
end
```

Any event not in the `EventRegistry` is flagged as unknown — these are candidates for new protocol documentation.

### Command-Response Correlations

```elixir
correlations = ZoomGate.Analyzer.get_correlations("my-session")

for c <- correlations do
  IO.puts("#{c.command.event_info.name} → #{length(c.responses)} responses, #{c.latency_us}µs")
end
```

Known patterns: `admit → roster`, `chat → confirmation`, `expel → roster remove`, `join → join response`, etc.

### Heuristic Pattern Discovery

For commands without known patterns, the correlator can suggest new patterns based on timing proximity:

```elixir
alias ZoomGate.Analyzer.{Recorder, Correlator}

records = Recorder.get_all("my-session")
suggestions = Correlator.discover_patterns(records)

for s <- suggestions do
  IO.puts("evt=#{s.command_evt} → evt=#{s.response_evt} (#{s.occurrences}x, avg #{s.avg_latency_us}µs)")
end
```

## Subscribing to Live State Changes

```elixir
# Subscribe to state changes
ZoomGate.Analyzer.subscribe("my-session")

# Receive changes in your process
receive do
  {:analyzer, {:state_changes, changes}} ->
    for change <- changes do
      case change do
        {:participant_added, data} -> IO.puts("Joined: #{data.participant.display_name}")
        {:participant_removed, data} -> IO.puts("Left: #{data.id}")
        {:setting_changed, field, old, new} -> IO.puts("Setting #{field}: #{old} → #{new}")
        {:unknown_event, evt, body} -> IO.puts("NEW EVENT: #{evt}")
        _ -> :ok
      end
    end
end
```

### Telemetry Events

All state changes emit `:telemetry` events:

```elixir
:telemetry.attach("my-handler", [:zoom_gate, :analyzer, :unknown_event], fn _name, _measurements, meta, _config ->
  IO.puts("Discovered: evt=#{meta.evt} body=#{inspect(meta.body)}")
end, nil)
```

Available events:
- `[:zoom_gate, :analyzer, :participant_added]`
- `[:zoom_gate, :analyzer, :participant_removed]`
- `[:zoom_gate, :analyzer, :participant_updated]`
- `[:zoom_gate, :analyzer, :setting_changed]`
- `[:zoom_gate, :analyzer, :chat_received]`
- `[:zoom_gate, :analyzer, :status_changed]`
- `[:zoom_gate, :analyzer, :unknown_event]`

## Client State Model

The analyzer maintains the same state as a native Zoom client:

```elixir
state = ZoomGate.Analyzer.get_state("my-session")

state.status             # :disconnected | :active | :waiting_room | :ended
state.self_user_id       # bot's user ID
state.self_role          # 0=participant, 1=host
state.participants       # %{user_id => EnrichedParticipant}
state.meeting_settings   # MeetingSettings struct
state.chat_history       # [ChatMessage]
```

### EnrichedParticipant

Extended participant with 30+ fields (vs 9 in the base `Participant`):

```elixir
p = state.participants[user_id]

# Core
p.display_name, p.role, p.is_host, p.is_cohost

# Media state
p.muted, p.video_on, p.b_share_on, p.hand_raised

# Extended identity
p.user_guid, p.str_conf_user_id, p.email, p.customer_key

# Unknown fields (auto-captured)
p.raw_extra  # %{"bAICompanionMgr" => true, "sdkKey" => "...", ...}
```

Fields not explicitly mapped are automatically captured in `raw_extra` for discovery.

### MeetingSettings

All known evt 7938 fields tracked, unknown fields in `raw_extra`:

```elixir
s = state.meeting_settings

s.b_lock, s.b_hold_upon_entry, s.chat_priviledge, s.b_muted_all
s.raw_extra  # %{"bAllowScreenCapture" => true, "lockShare" => 0, ...}
```

## Event Registry

The registry catalogs ~196 known RWG events. Query it directly:

```elixir
alias ZoomGate.Analyzer.EventRegistry

EventRegistry.lookup(7937)                     # {:ok, %EventInfo{name: "roster", ...}}
EventRegistry.known?(4260)                     # true
EventRegistry.events_by_category(:breakout)    # [%EventInfo{}, ...]
EventRegistry.categories()                     # [:ai, :annotation, :audio, ...]
```

Events discovered by the analyzer are added with `[unconfirmed]` in their description.

## Export for Offline Analysis

```elixir
data = ZoomGate.Analyzer.export("my-session")
File.write!("session.json", Jason.encode!(data, pretty: true))
```

Each exported record includes: `id`, `direction`, `evt`, `body`, `seq`, `is_known`, `wall_clock`, `category`, `name`.

## Troubleshooting

### Error 3099: Meeting registration required

Participants (`role: 0`) may get redirected to a registration URL. The host (`role: 1`) can join
without registration. **Workaround:** Use `role: 1` for all bots — they join as co-hosts and bypass
registration requirements.

### Error 3000: Already has other meetings in progress

A Zoom account can only host one active meeting at a time. If you start a new meeting while the
bot is still connected to the previous one, this error occurs.
**Fix:** Call `MeetingBot.leave(bot)` and wait before starting a new session.

```elixir
# Always clean up before starting a new session
ZoomGate.MeetingBot.leave(old_bot)
Process.sleep(2000)
```

### ZAK scope missing (error 4711)

If `ZoomGate.ZoomAPI.get_zak/1` returns `{:error, {400, ...}}`, the S2S OAuth app is missing
the `user:read:zak:admin` scope. Add it in Zoom Marketplace → S2S OAuth App → Scopes.

## SDK Credential Notes

Two separate Zoom Marketplace apps are used:

- **General App** (Meeting SDK) — `ZOOM_SDK_KEY` (Client ID) + `ZOOM_SDK_SECRET` (Client Secret)
  - Used by `MeetingBot` to sign the JWT for RWG WebSocket connection
  - These are the Meeting SDK credentials, NOT the S2S OAuth ones

- **Server-to-Server OAuth App** — `ZOOM_ACCOUNT_ID` + `ZOOM_CLIENT_ID` + `ZOOM_CLIENT_SECRET`
  - Used by `ZoomGate.ZoomAPI` for REST API calls (create meetings, get ZAK, etc.)
  - Token endpoint: `POST https://zoom.us/oauth/token?grant_type=account_credentials&account_id=...`
  - Tokens expire in 1 hour, re-fetch via `ZoomGate.ZoomAPI.get_access_token/0`
  - Required scopes: `meeting:write:admin` (create meetings), `user:read:zak:admin` (ZAK tokens)
