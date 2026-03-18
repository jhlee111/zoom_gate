---
name: release
description: Run full Elixir preflight, bump version, and create a GitHub release
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

## Step 1: Full Preflight

Run ALL checks. Every check must pass before releasing.

```bash
# 1. Clean compile — catch all warnings
mix deps.get
mix compile --warnings-as-errors

# 2. Format check
mix format --check-formatted

# 3. Full test suite
mix test

# 4. Static analysis
mix credo --strict

# 5. Check for unused dependencies
mix deps.unlock --check-unused

# 6. Generate docs (catch broken links, missing moduledocs)
mix docs
```

If any check fails, STOP and fix before proceeding.

## Step 2: Security Scan

```bash
# Check for secrets in the entire codebase
git diff HEAD --name-only | xargs grep -l -i 'secret\|password\|token\|api_key' 2>/dev/null || true
```

Review any flagged files. Ensure no real credentials are committed.

## Step 3: Determine Version

```bash
# Current version
grep 'version:' mix.exs

# Changes since last tag
git log $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~10)..HEAD --oneline
```

Apply SemVer rules:
- **Patch** (0.x.Y): bug fixes, docs, minor improvements
- **Minor** (0.X.0): new features, non-breaking API additions
- **Major** (X.0.0): breaking API changes (post-1.0 only)

Ask the user to confirm the version number.

## Step 4: Update Version

```elixir
# mix.exs
version: "0.x.y"
```

## Step 5: Update CHANGELOG.md

Create if missing. Follow Keep a Changelog format:

```markdown
## [0.x.y] - YYYY-MM-DD

### Added
- Feature descriptions

### Fixed
- Bug fix descriptions

### Changed
- Change descriptions
```

## Step 6: Commit and Tag

```bash
git add mix.exs CHANGELOG.md
git commit -m "chore: release v0.x.y

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"

git tag -a v0.x.y -m "Release v0.x.y"
```

Ask the user before pushing:

```bash
git push origin main --tags
```

## Step 7: Create GitHub Release

```bash
gh release create v0.x.y --title "v0.x.y" --notes "$(cat <<'EOF'
## What's New
- <summary of changes>

## Preflight
- `mix compile --warnings-as-errors` ✓
- `mix format --check-formatted` ✓
- `mix test` (N tests, 0 failures) ✓
- `mix docs` ✓

## Full Changelog
https://github.com/jhlee111/zoom_gate/compare/v0.x.z...v0.x.y
EOF
)"
```

## Step 8: Post-Release (if applicable)

Close milestone if all issues are done:
```bash
# List milestone issues
gh issue list --milestone "<milestone name>"

# If all closed, close the milestone
gh api repos/jhlee111/zoom_gate/milestones/<N> -X PATCH -f state=closed
```

Docker image (if deployment-related release):
```bash
docker build -t zoomgate/zoomgate:0.x.y -t zoomgate/zoomgate:latest .
docker push zoomgate/zoomgate:0.x.y
docker push zoomgate/zoomgate:latest
```
