---
name: update-docs
description: Update project documentation after completing work
user_invocable: true
---

# Update Documentation Skill for ZoomGate

## Documentation Locations

### 1. Code Docs (Primary)
- `@moduledoc` on all public modules
- `@doc` on all public functions
- This is the Elixir way — discoverable via `h Module` in IEx

### 2. README.md (Project root)
- Project overview and quick start
- API usage examples (BEAM, WebSocket, REST)
- Docker deployment instructions
- Update when: new API endpoints, new features, deployment changes

### 3. GitHub Issues & Milestones
- All work tracked at https://github.com/jhlee111/zoom_gate/issues
- Issues are organized into milestones (P1–P5)
- Close issues when work is done: `gh issue close <number>`
- Update issue comments with findings for research issues
- Check milestone progress: `gh api repos/:owner/:repo/milestones --jq '.[] | "\(.title): \(.open_issues) open / \(.closed_issues) closed"'`
- Close milestone when all issues done: `gh api repos/:owner/:repo/milestones/<N> -X PATCH -f state=closed`

### 4. CLAUDE.md
- Update when: project structure changes, new conventions, new related projects

### 5. CHANGELOG.md
- Update on releases
- Follow [Keep a Changelog](https://keepachangelog.com/) format

## After Completing Work

1. **Update @moduledoc** if module behavior changed
2. **Close related GitHub issue** with summary comment
3. **Check milestone progress** — if all issues in milestone are closed, close the milestone
4. **Update README.md** if public API changed
5. **Update CLAUDE.md** if project structure or conventions changed

## Process

```bash
# Check what issues are open
gh issue list

# Filter by milestone
gh issue list --milestone "P2: Core OTP"

# Close an issue with comment
gh issue close <number> --comment "Completed in <commit/PR>"

# Update issue with findings
gh issue comment <number> --body "Findings: ..."

# Check milestone progress
gh api repos/:owner/:repo/milestones --jq '.[] | "\(.title): \(.open_issues) open / \(.closed_issues) closed"'

# Close completed milestone
gh api repos/:owner/:repo/milestones/<N> -X PATCH -f state=closed
```
