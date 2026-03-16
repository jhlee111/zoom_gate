---
name: pr
description: Create a pull request following ZoomGate conventions
user_invocable: true
---

# Pull Request Skill for ZoomGate

## PR Creation Process

1. Check current branch and changes:
   ```bash
   git status
   git log main..HEAD --oneline
   git diff main...HEAD --stat
   ```

2. Push branch if needed:
   ```bash
   git push -u origin <branch-name>
   ```

3. Create PR with `gh pr create`:
   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   - <bullet points>

   ## Related Issues
   Closes #<number>

   ## Test Plan
   - [ ] <test checklist>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

## PR Title Convention

- Under 70 characters
- Format: `<type>(<scope>): <description>`
- Examples:
  - `feat(session): implement waiting room event handling`
  - `feat(channel): add Phoenix Channel WebSocket API`
  - `fix(worker): resolve stdout buffering issue`

## Branch Naming

```
feature/p2-session-genserver
feature/p3-cpp-worker
fix/port-buffer-overflow
docs/api-examples
```

## Checklist Before PR

- [ ] `mix format` passes
- [ ] `mix test` passes
- [ ] Related issue linked with `Closes #N`
- [ ] No secrets or credentials in diff
