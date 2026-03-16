---
name: release
description: Create a new release following SemVer
user_invocable: true
---

# Release Skill for ZoomGate

## Versioning (SemVer) — Milestone Aligned

| Version | Milestone | Scope |
|---------|-----------|-------|
| `0.1.x` | P2: Core OTP | Session GenServer + Protocol |
| `0.2.x` | P3: C++ SDK Worker | Native SDK wrapper |
| `0.3.x` | P4: API Layer | WebSocket + REST + BEAM Cluster |
| `0.4.x` | P5: Deployment | Docker image |
| `1.0.0` | — | Production ready |

Note: P1 (Zoom Marketplace App) is infra setup — no code release.

## Release Process

1. **Check current version:**
   ```bash
   grep 'version:' mix.exs
   ```

2. **Update version in `mix.exs`:**
   ```elixir
   version: "0.x.y"
   ```

3. **Update CHANGELOG.md** (create if missing):
   ```markdown
   ## [0.x.y] - YYYY-MM-DD

   ### Added
   - Feature description

   ### Fixed
   - Bug fix description

   ### Changed
   - Change description
   ```

4. **Commit version bump:**
   ```bash
   git add mix.exs CHANGELOG.md
   git commit -m "chore: release v0.x.y"
   ```

5. **Create git tag:**
   ```bash
   git tag -a v0.x.y -m "Release v0.x.y"
   git push origin main --tags
   ```

6. **Create GitHub release:**
   ```bash
   gh release create v0.x.y --title "v0.x.y" --notes "$(cat <<'EOF'
   ## What's New
   - <summary>

   ## Full Changelog
   https://github.com/jhlee111/zoom_gate/compare/v0.x.z...v0.x.y
   EOF
   )"
   ```

7. **Docker image** (if applicable):
   ```bash
   docker build -t zoomgate/zoomgate:0.x.y -t zoomgate/zoomgate:latest .
   docker push zoomgate/zoomgate:0.x.y
   docker push zoomgate/zoomgate:latest
   ```

## Pre-release Checklist

- [ ] All tests pass (`mix test`)
- [ ] Code formatted (`mix format --check-formatted`)
- [ ] No compiler warnings (`mix compile --warnings-as-errors`)
- [ ] CHANGELOG.md updated
- [ ] Version bumped in mix.exs
- [ ] Related issues closed
- [ ] Milestone closed if all issues done (`gh api repos/:owner/:repo/milestones/<N> -X PATCH -f state=closed`)
- [ ] Docker build successful (if applicable)
