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

### 3. GitHub Issues
- All work tracked at https://github.com/jhlee111/zoom_gate/issues
- Close issues when work is done: `gh issue close <number>`
- Update issue comments with findings for research issues

### 4. CLAUDE.md
- Update when: project structure changes, new conventions, new related projects

### 5. CHANGELOG.md
- Update on releases
- Follow [Keep a Changelog](https://keepachangelog.com/) format

## After Completing Work

1. **Update @moduledoc** if module behavior changed
2. **Close related GitHub issue** with summary comment
3. **Update README.md** if public API changed
4. **Update CLAUDE.md** if project structure or conventions changed

## Process

```bash
# Check what issues are open
gh issue list

# Close an issue with comment
gh issue close <number> --comment "Completed in <commit/PR>"

# Update issue with findings
gh issue comment <number> --body "Findings: ..."
```
