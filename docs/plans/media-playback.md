# Plan: Media Playback (Two-Bot Architecture)

Implementation plan for the decision in
[`docs/adr/0001-media-playback-architecture.md`](../adr/0001-media-playback-architecture.md).

Branch: `claude/bot-video-playback-1ZjMY`.

## Goal

Enable ZoomGate consumers to play pre-recorded video + audio into an
active Zoom meeting, with playback controls (pause / resume / skip /
seek), eventually with playlist and subtitle support. Target 5 concurrent
sessions on a single host.

## Approach summary

- Add a new sidecar service, `zoom_mediabot`, under `mediabot/` in this
  monorepo.
- `zoom_mediabot` exposes a small HTTP API.
- Each playback session corresponds to one `zoom_mediabot` worker
  subprocess that joins the meeting as an independent Zoom participant
  (separate from the existing ZoomGate control bot).
- ZoomGate pre-registers the media bot's identifier (an `email` field),
  detects its arrival in the waiting room via existing RWG roster
  events, and admits it automatically.
- All coordination is via ZoomGate ↔ `zoom_mediabot` HTTP. The two bots
  never talk to each other; they meet only in the Zoom meeting itself.

## Phases

### Phase 0 — Spike: validate Option A (2 days)

Goal: De-risk Option A before committing.

Tasks:

- [ ] Confirm the Zoom official sample
      `zoom/meetingsdk-headless-linux-sample` is current and
      Apache-licensed.
- [ ] Run the sample locally: build, link against the Linux Meeting SDK,
      join a test meeting as a bot, play an MP4 from disk.
- [ ] Verify a separate test client sees the bot's video and hears
      audio.
- [ ] Reproduce the build in a GitHub Actions runner (the SDK download
      step must work in CI with a stored credential).
- [ ] Decide: commit to A, or fall back to B.

Acceptance:

- A bot session plays a 30 s test MP4 end-to-end in a real meeting.
- The same build runs green in CI.

Exit:

- If A passes → proceed to Phase 1 building on the sample.
- If A fails → spike Option B for 1–2 days (`v4l2loopback` + headless
  Chrome + Zoom Web SDK joining a meeting and consuming a virtual
  device). On success, switch the rest of this plan to B.

### Phase 1 — MVP: single-video playback (1 session, no controls)

Goal: One mediabot can join a meeting and play one MP4 from a URL,
end-to-end, with ZoomGate orchestrating.

Tasks:

- [ ] Create `mediabot/` subdirectory with `Dockerfile`,
      `CMakeLists.txt`, `worker/`, `orchestrator/`.
- [ ] Worker (C++): SDK init → auth (JWT) → meeting join → FFmpeg
      decode loop → push YUV420 frames via `IZoomSDKVideoSource` and
      PCM via `IZoomSDKVirtualAudioMic` → leave on EOF.
- [ ] Orchestrator HTTP server (Go or Elixir — see open question OQ-1):
      `POST /sessions` spawns a worker subprocess; `GET /sessions/:id`
      returns state; `DELETE /sessions/:id` kills it.
- [ ] Worker reports state to orchestrator via stdout JSON lines
      (state, position, error).
- [ ] ZoomGate side: `ZoomGate.MediaBot` GenServer (HTTP client to
      mediabot), and `ZoomGate.play_media/3`, `ZoomGate.stop_media/1`
      public API.
- [ ] ZoomGate Session pre-registers a media-bot email in its state,
      auto-admits when the matching identifier appears in roster /
      `evt_hold_change`.
- [ ] Verify the `Participant.merge_roster` pipeline actually surfaces
      the `email` field. If not, choose an alternative identifier.
- [ ] docker-compose with `zoom_gate` and `zoom_mediabot` services on
      localhost.

Acceptance:

- From a test app, call `ZoomGate.play_media(meeting_id, video_url)`,
  see the media bot enter the meeting and play the video to a separate
  human participant.
- Stop with `ZoomGate.stop_media(meeting_id)`; the bot leaves cleanly.

Risks:

- RWG roster may not expose `email` in the shape we expect. Mitigation:
  capture full roster payload during Phase 1 testing; fall back to
  another reliable pre-registerable field.
- Bot's video/audio may be muted or video-off on join. Mitigation: in
  the worker, explicitly request video-on and audio-on after join.

### Phase 2 — Playback controls

Goal: pause / resume / skip / seek work mid-playback.

Tasks:

- [ ] Worker: add internal state machine
      `idle → ready → playing ⇄ paused`, with `seek(t)` and
      `skip_to_next` transitions.
- [ ] Orchestrator: add `POST /sessions/:id/pause`, `.../resume`,
      `.../seek`, `.../skip` endpoints — forward as commands to worker
      stdin.
- [ ] ZoomGate: expose `ZoomGate.pause_media/1`, `.resume_media/1`,
      `.seek_media/2`, `.skip_media/1` as the public API surface.
- [ ] Webhook events back to ZoomGate: `playing`, `paused`,
      `position`, `track_ended`, `error`.

Acceptance:

- Test app drives pause/resume/seek; participants see the change with
  expected delay (< 1 s).

### Phase 3 — Playlist

Goal: a session plays a sequence of items; auto-advance on item end.

Tasks:

- [ ] Worker: maintain `playlist: [item]` and `current_index`; on EOF
      of current item, decode next.
- [ ] Orchestrator: `POST /sessions/:id/playlist` (replace),
      `POST /sessions/:id/playlist/append`,
      `POST /sessions/:id/skip` (already in Phase 2) advances index.
- [ ] ZoomGate API: `ZoomGate.set_playlist/2`,
      `ZoomGate.append_playlist/2`, `ZoomGate.skip_track/1`.
- [ ] Webhook event `track_changed` carrying new index + item metadata.

Acceptance:

- A 3-item playlist plays back-to-back without re-creating the session
  or rejoining the meeting.

### Phase 4 — Subtitles

Goal: subtitle support, starting with burn-in.

Tasks:

- [ ] Worker: accept `subtitle_url` per item; if present, configure
      FFmpeg `subtitles` filter when decoding.
- [ ] Optional later: Zoom Closed Captioning API path — worker emits
      position events, ZoomGate sends CC text events via RWG. This
      requires adding CC opcodes to
      `lib/zoom_gate/meeting_bot/protocol.ex`.

Acceptance:

- A playlist item with an SRT renders captions in the video sent to the
  meeting.

### Phase 5 — Concurrency: 5 sessions on one host

Goal: 5 simultaneous playback sessions on the target server.

Tasks:

- [ ] Stress test: 5 sessions, each playing a 30 min video, observe
      CPU, RAM, network upload.
- [ ] Tune: worker per-session resource budget; orchestrator concurrent
      session cap; consider VA-API / NVENC if CPU-bound.
- [ ] Define container sizing in Docker Compose limits.

Acceptance:

- 5 concurrent sessions stable for 30 min with < 80% CPU and no
  failures.

## Open questions

| ID | Question | Resolution path |
|----|----------|-----------------|
| OQ-1 | Orchestrator language (Go vs Elixir)? | Decide during Phase 1 design; default Go. |
| OQ-2 | Credential transport ZG → mediabot (env var, short-lived token, or per-request payload)? | Per-request payload for v1 (internal network). |
| OQ-3 | Media file source (S3 presigned URL, local volume, plain HTTPS URL)? | HTTPS URL accepted by worker; consumer chooses. |
| OQ-4 | Identifier field for auto-admit (`email` confirmed via roster, or another)? | Verify in Phase 1 implementation. |
| OQ-5 | Subtitles mode for v1 (burn-in vs CC)? | Burn-in. CC deferred to later phase. |
| OQ-6 | Concurrent ceiling beyond 5? Trigger for K8s migration? | Revisit after Phase 5 measurements. |
| OQ-7 | Failure semantics: media bot crashes mid-playlist — restart? skip? notify only? | Decide during Phase 3. |
| OQ-8 | Should the control bot's Session GenServer become `durable_server`-backed for HA later? | Out of scope of this plan; track separately. |

## Out of scope

- Receiving raw data from the meeting (recording participants). The
  separate Raw Data **receive** capability requires Zoom approval and
  is unrelated.
- Multi-host deployment / Kubernetes Jobs. Triggered only if Phase 5
  measurements exceed single-host capacity.
- Marketplace publication. Internal-only use; no submission needed.

## Housekeeping (separate from feature work)

- [ ] Update `CLAUDE.md` — the current document still describes a
      C++-SDK-over-Port architecture that no longer matches reality.
      Reflect the pure-Elixir RWG client and the new two-bot media
      split.
- [ ] Decide fate of `native/zoom_worker.cpp` and the `worker_path`
      config entry. If Phase 0 commits to Option A, evolve the file
      into the new mediabot worker. Otherwise delete.
- [ ] Verify `Participant.merge_roster` and `participant.ex` actually
      expose `email`. If not, plumb it through (small, isolated
      change).
