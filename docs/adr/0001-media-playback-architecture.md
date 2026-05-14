# ADR 0001: Media Playback Architecture

- **Status**: Proposed
- **Date**: 2026-05-14
- **Branch**: `claude/bot-video-playback-1ZjMY`

## Context

ZoomGate currently exposes Zoom waiting-room access control by joining a
meeting as a lightweight pure-Elixir bot that speaks Zoom's RWG WebSocket
protocol directly (~10 MB image, no SDK, no browser).

A new requirement: the system must be able to **play a pre-recorded video
(with audio)** into a meeting so participants see and hear it as if a
participant were sharing media. Concrete shape of the requirement:

- Video + audio together (audio-only is not acceptable; video is 99% of use)
- Long-form content (30 min+ per item)
- Eventually: playlist of items, with subtitle support
- Playback controls from the controlling app: pause, resume, skip, seek
- Concurrent target: **5 sessions** on a single host (YAGNI ceiling)
- Acceptable start latency: **5 s**
- Internal-only deployment (no Zoom Marketplace listing required)

### Why the current architecture cannot do this

The RWG WebSocket is a signalling/control channel only. It carries roster
events, hold-change, chat, mute, expel, etc. — but no media plane. The
official Zoom clients carry media over a separate WebRTC (Web SDK) or
internal proprietary transport (Native SDK). To send media as a bot, we
need an actual SDK integration; reverse-engineering the WebRTC media
plane is not realistic.

## Decision

Adopt a **two-bot split architecture**: every meeting that needs media
playback has **two independent Zoom participants**, each handled by a
different service:

```
┌─ Application (GsNet etc.) ───────────────────────────────────────┐
│                                                                  │
└────────────────┬─────────────────────────────────────────────────┘
                 │ BEAM / WS / REST
                 ↓
┌─ zoom_gate (Elixir, ~10 MB) ─────────────────────── Control plane │
│  • Session GenServer per meeting                                 │
│  • RWG WebSocket — waiting-room admit/deny/chat/expel/mute       │
│  • MediaBot orchestrator client (HTTP)                           │
└────────────────┬───────────────────────┬─────────────────────────┘
                 │ join as Bot#1         │ HTTP /sessions
                 │ (signalling only)     ↓
                 ↓                ┌─ zoom_mediabot (~ hundreds MB) ─┐
          ┌──────────────┐        │ • Native SDK or headless Chrome │
          │  Zoom cloud  │ ← Bot#2│ • FFmpeg media pipeline         │
          │  (meeting)   │ join   │ • Per-session worker subprocess │
          └──────────────┘        │ • HTTP API for control          │
                                  └─────────────────────────────────┘
```

### Key properties

1. **The two bots do not talk to each other directly.** Both join the
   meeting as independent Zoom participants. Coordination is done by
   the orchestrator (ZoomGate).
2. **The control bot pre-registers the media bot.** When ZoomGate is
   asked to play media, it (a) records an expected identifier in its
   Session state, (b) tells `zoom_mediabot` to join, (c) when the bot
   appears in the RWG waiting-room event with that identifier, ZoomGate
   immediately admits it.
3. **Identifier field**: `email` (e.g., `mediabot-<uuid>@internal.local`).
   `display_name` is reserved for app-controlled labels visible to
   participants (e.g. session title). Pre-registration uses email so
   display_name can be anything.
4. **HTTP interface between ZoomGate and mediabot.** Not Erlang Port
   (would couple the heavy media stack to the BEAM image, defeating the
   10 MB control-plane goal), not `durable_server` (that solves
   GenServer-state persistence, not OS-process supervision).
5. **Co-located on a single host at first.** Docker Compose with two
   services on `localhost`. Same HTTP interface migrates unchanged to
   K8s when scale demands it.
6. **`zoom_mediabot` lives in this monorepo** under `mediabot/`.

### Internal implementation of `zoom_mediabot`: A vs B

Two candidate implementations were considered:

- **Option A — Native C++ Zoom Meeting SDK for Linux** + `IZoomSDKVideoSource`
  + `IZoomSDKVirtualAudioMic` + FFmpeg media pipeline.
- **Option B — Headless Chromium + Zoom Web SDK** + virtual webcam
  (`v4l2loopback`) + virtual mic (PulseAudio null sink) + FFmpeg piping
  raw frames into the kernel devices.

For the requirement set (30 min+ playback, 5 s start latency, native
control surface for pause/skip/seek, dev team owning both build
pipelines, GitHub Actions C++ build acceptable), **Option A is the
better long-term fit**:

|                          | A (Native SDK) | B (Headless Chrome) |
|--------------------------|----------------|---------------------|
| Per-session memory       | ~150–200 MB    | ~400–500 MB         |
| Per-session start time   | 2–3 s ✅       | 5–15 s ⚠️           |
| Long-form stability      | High           | Browser lifecycle risk |
| Image size               | ~600 MB        | ~1.2 GB             |
| Single-host ceiling      | ~30–50 sessions| ~10–15 sessions     |
| Time to PoC              | 2–4 weeks      | ~1 week             |
| Build complexity         | High (SDK)     | Low (npm + chromium)|
| Observability            | Lower (SDK black box) | Higher (DevTools) |

### Spike before commitment

Before fully committing to A, run a **2-day spike** against Zoom's
official sample (`meetingsdk-headless-linux-sample`, Apache 2.0). Goals:

1. Day 1: Build the sample in GitHub Actions, confirm Zoom SDK download
   pipeline is workable inside CI.
2. Day 2: Run the sample locally; join a test meeting as a bot; play an
   MP4 from disk into the meeting; verify another client sees video +
   hears audio.

- If spike succeeds → **commit to A**; `zoom_mediabot` is built on the
  sample as a starting point.
- If spike fails (sample is broken/abandoned, or license blocks CI
  build) → **fall back to B**.

### Why not Erlang Port

A Port would spawn the mediabot binary as a child of the BEAM, which
forces co-location on a single host *and* drags all heavy media
dependencies (Chromium or Zoom SDK shared libs) into the same OS image
as the 10 MB control plane. This breaks the separation that justified
the split in the first place. Sidecar-container + localhost HTTP keeps
the same single-host deployment shape with proper isolation, and ports
forward unchanged when we eventually scale out.

### Why not `durable_server`

`durable_server` provides automatic persistence and cluster-wide
re-placement for *in-BEAM GenServer state*. It does not supervise OS
processes. It may later be useful to harden the ZoomGate `Session`
GenServer itself across BEAM node failures, but that is an unrelated
concern.

## Server platform

- **CPU architecture**: x86_64 (Zoom Meeting SDK is first-class on
  x86_64; arm64 support lags and is intermittent; hardware video
  encoding offload — VA-API, NVENC — is mature on x86 servers).
- **OS**: Ubuntu 22.04 LTS (Zoom Linux SDK supported).
- **Initial sizing** (target 5 concurrent sessions): 16 vCPU, 32 GB
  RAM, NVMe storage for media cache, 1 Gbps NIC. Optional NVIDIA T4/L4
  for NVENC if CPU encoding becomes the bottleneck.

## Consequences

### Positive

- The 10 MB pure-Elixir control plane stays unchanged. No regression
  for users who only need waiting-room control.
- Media plane can fail, restart, or be deployed independently of the
  control plane.
- HTTP interface lets the media bot be re-implemented later (A↔B↔C)
  without touching ZoomGate code.
- Single-host docker-compose for v1 keeps operational complexity low;
  same interface scales to per-session K8s Jobs when needed.

### Negative

- Two Zoom participants per "playing meeting" — visible in the roster
  to host. Naming convention (e.g., display_name = session title;
  email = internal UUID) needed.
- The control bot must admit the media bot from the waiting room. If
  the control bot is unhealthy at the moment the media bot joins, the
  media bot stalls in the waiting room.
- Two SDK credential paths to manage (RWG via Web SDK signature + Raw
  Data via Native SDK), though they can share the same Marketplace app.
- A's path requires the team to own a C++ build pipeline.

### Neutral / to revisit

- Subtitle delivery: burn-in (FFmpeg `subtitles` filter) for PoC,
  Zoom Closed Captioning API later for toggleable / multi-language
  captions. The RWG protocol module does not yet have CC opcodes.
- Whether `zoom_mediabot`'s internal HTTP orchestrator is Go or Elixir
  is deferred. Worker is C++ regardless.

## Open questions

Tracked in `docs/plans/media-playback.md`.

## References

- Zoom Meeting SDK for Linux — Raw Data: `IZoomSDKVideoSource`,
  `IZoomSDKVirtualAudioMic`.
- Zoom official sample: `zoom/meetingsdk-headless-linux-sample`
  (Apache 2.0). Validate URL during spike.
- `lib/zoom_gate/meeting_bot.ex` — current pure-Elixir RWG client.
- `lib/zoom_gate/session.ex` — pluggable bot module via
  `:zoom_gate, :bot_module` config.
