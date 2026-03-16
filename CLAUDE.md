# Claude Code Instructions for ZoomGate

## Project Overview

ZoomGate is a Zoom Meeting SDK bridge that exposes waiting room access control as a service.
Built with Elixir/OTP, wrapping the Zoom Native C++ SDK via Erlang Ports.

**Repository**: https://github.com/jhlee111/zoom_gate
**Language**: Elixir + C++ (native SDK wrapper)
**Target Platform**: Linux x86_64 (Docker)

---

## Architecture

```
ZoomGate.Application
├── Registry (meeting_id → Session PID)
├── SessionSupervisor (DynamicSupervisor)
│   └── Session (GenServer) × N
│       └── Port → zoom_worker (C++ binary)
├── Endpoint (Phoenix)
│   ├── WebSocket (Phoenix Channel)
│   └── REST API (Plug Router)
└── ClusterSupervisor (libcluster)
```

### Key Design Principles

1. **Pure SDK proxy** — ZoomGate has ZERO business logic. It receives commands, calls SDK functions, and emits events. All decision-making belongs to the consuming application.
2. **Per-meeting GenServer** — Each active meeting gets its own `Session` GenServer managing a C++ worker Port.
3. **3-layer API** — BEAM cluster (Elixir native), WebSocket (Phoenix Channel), REST + Webhooks.
4. **Port over NIF** — C++ SDK crashes must not kill the BEAM VM.

### C++ Worker Protocol (stdin/stdout JSON)

Commands (stdin):
```json
{"command":"admit","zoom_user_id":12345,"display_name":"홍길동"}
{"command":"deny","zoom_user_id":12345,"message":"Not authorized"}
{"command":"rename","zoom_user_id":12345,"display_name":"New Name"}
{"command":"expel","zoom_user_id":12345}
{"command":"chat","message":"Hello","to":12345}
{"command":"leave"}
```

Events (stdout):
```json
{"event":"joined"}
{"event":"waiting_room_join","zoom_user_id":12345,"display_name":"John","email":"j@x.com"}
{"event":"waiting_room_leave","zoom_user_id":12345}
{"event":"participant_joined","zoom_user_id":12345,"display_name":"John"}
{"event":"participant_left","zoom_user_id":12345}
{"event":"meeting_ended"}
{"event":"error","code":1234,"message":"SDK error"}
```

---

## Project Structure

```
zoom_gate/
├── CLAUDE.md                       # This file
├── mix.exs                         # Elixir project
├── lib/
│   ├── zoom_gate.ex                # Public API (defdelegate)
│   └── zoom_gate/
│       ├── application.ex          # OTP Application
│       ├── session_supervisor.ex   # DynamicSupervisor
│       ├── session.ex              # GenServer (core)
│       ├── protocol.ex             # JSON protocol spec
│       ├── endpoint.ex             # Phoenix Endpoint
│       ├── socket.ex               # Phoenix Socket
│       ├── gate_channel.ex         # Phoenix Channel (WebSocket API)
│       ├── router.ex               # Plug Router (REST API)
│       └── controllers/
│           └── session_controller.ex
├── native/                         # C++ SDK worker
│   ├── CMakeLists.txt
│   ├── zoom_worker.cpp
│   └── zoom-meeting-sdk/           # gitignored
├── test/
├── config/
├── Dockerfile
└── .claude/
    └── skills/
```

---

## Development Commands

```bash
# Elixir
mix deps.get
mix compile
mix test
mix format

# C++ worker (native/)
cd native && mkdir -p build && cd build
cmake .. && make

# Docker
docker build -t zoomgate:latest .
docker run -d -e ZOOM_SDK_KEY=... -e ZOOM_SDK_SECRET=... -p 4000:4000 zoomgate:latest
```

---

## Git Conventions

### Branch Naming

Format: `<type>/<milestone-short>-<description>`

```
feature/p2-session-genserver
feature/p3-cpp-worker
feature/p4-websocket-api
fix/port-buffer-overflow
docs/readme-api-examples
```

Milestone short names: `p1`, `p2`, `p3`, `p4`, `p5`

### Commit Message Format

```
feat(session): add waiting room event handling
fix(worker): flush stdout after each JSON line
docs(api): add WebSocket client examples
refactor(protocol): extract command encoding
test(session): mock port for unit tests
chore(docker): add multi-stage build
```

### PR Conventions

- PRs target `main` branch
- Title: concise, under 70 characters
- Body: Summary bullets + test plan
- Link related GitHub issues

### Release Versioning

Semantic versioning (SemVer), aligned with milestones:

| Version | Milestone | Scope |
|---------|-----------|-------|
| `0.1.x` | P2: Core OTP | Session GenServer + Protocol |
| `0.2.x` | P3: C++ SDK Worker | Native SDK wrapper |
| `0.3.x` | P4: API Layer | WebSocket + REST + BEAM Cluster |
| `0.4.x` | P5: Deployment | Docker image |
| `1.0.0` | — | Production ready |

Note: P1 (Zoom Marketplace App) is infra setup — no code release.

---

## Code Style

- Follow standard Elixir conventions (`mix format`)
- Module docs (`@moduledoc`) for all public modules
- Function docs (`@doc`) for public functions
- No unnecessary abstractions — this is a thin wrapper
- C++ code: modern C++ (C++17), nlohmann/json for JSON
- C++ naming: snake_case for functions, PascalCase for classes

---

## Related Projects

| Project | Location | Relationship |
|---------|----------|-------------|
| GsNet | `/Users/johndev/Dev/gs_net` | Primary consumer (BEAM cluster) |
| ash_grant | `/Users/johndev/Dev/ash_grant` | Authorization library (GsNet uses) |

### GsNet Integration Points

GsNet consumes ZoomGate via BEAM cluster:
- `GsNet.Integrations.Zoom.BridgeClient` — calls ZoomGate GenServers
- `GsNet.Integrations.Zoom.AdmissionHandler` — handles waiting room events
- `GsNet.Integrations.Zoom.ZoomAccount` — Ash resource for OAuth accounts
- `GsNet.Integrations.Zoom.ZoomMeeting` — Ash resource for meeting data

---

## GitHub Project Tracking

All work is tracked in GitHub issues: https://github.com/jhlee111/zoom_gate/issues

### Milestones (Phases)

Issues are organized into milestones representing implementation phases:

| Milestone | Description |
|-----------|-------------|
| P1: Zoom Marketplace App | OAuth + Meeting SDK 설정 |
| P2: Core OTP | Session GenServer + DynamicSupervisor |
| P3: C++ SDK Worker | Zoom Native SDK C++ 래퍼 |
| P4: API Layer | WebSocket, REST, BEAM Cluster API |
| P5: Deployment | Docker image + deployment |

Use `gh issue list --milestone "P2: Core OTP"` to filter by milestone.

### Labels (Categories)

Labels are for technology/category only — NOT for phases:
- `research` — investigation tasks
- `c++` — C++ SDK worker
- `elixir` — Elixir/OTP
- `api` — API layers
- `infra` — infrastructure
- `documentation` — docs
