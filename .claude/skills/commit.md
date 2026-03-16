---
name: commit
description: Create a git commit following ZoomGate conventions
user_invocable: true
---

# Commit Skill for ZoomGate

## Commit Message Format

```
<type>(<scope>): <description>

[optional body]

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

### Types
- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation
- `refactor` — code restructure without behavior change
- `test` — tests
- `chore` — build, CI, dependencies

### Scopes
- `session` — Session GenServer
- `supervisor` — SessionSupervisor
- `protocol` — stdin/stdout JSON protocol
- `worker` — C++ SDK worker
- `channel` — Phoenix Channel (WebSocket API)
- `rest` — REST API
- `docker` — Docker/deployment
- `cluster` — BEAM cluster / libcluster

## Instructions

1. Run `git status` and `git diff` to see changes
2. Run `git log --oneline -5` to see recent commit style
3. Stage relevant files (specific files, not `git add .`)
4. Create commit with conventional message format
5. Verify with `git status` after commit
