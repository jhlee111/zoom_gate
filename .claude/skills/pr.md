---
name: pr
description: Run Elixir preflight checks and create a pull request following ZoomGate conventions
user_invocable: true
---

# Pull Request Skill for ZoomGate

## Step 1: Preflight Checks

Run ALL checks before creating the PR. Stop and fix any failures.

```bash
# 1. Format check (must pass — CI enforces this)
mix format --check-formatted

# 2. Compile with warnings-as-errors
mix compile --warnings-as-errors

# 3. Run full test suite
mix test

# 4. Static analysis
mix credo --strict

# 5. Check for unused dependencies
mix deps.unlock --check-unused
```

If any check fails, fix the issue and re-run before proceeding.

## Step 2: Security Scan

Before creating the PR, check the diff for leaked secrets:

```bash
git diff main...HEAD
```

Look for:
- API keys, tokens, passwords in plain text
- `.env` files or credentials files staged
- Hardcoded `sdk_key`, `sdk_secret`, `zak` values (not example placeholders)

If secrets are found, STOP and alert the user.

## Step 3: Analyze Changes

```bash
git status
git log main..HEAD --oneline
git diff main...HEAD --stat
```

Identify:
- Which modules were changed
- Whether tests cover the changes
- The appropriate milestone and related issues

## Step 4: Push Branch

```bash
# Create branch if still on main
# Branch format: <type>/<milestone-short>-<description>
# Examples: feature/p4-embedded-mode, fix/session-crash, docs/api-guide
git push -u origin <branch-name>
```

## Step 5: Identify Milestone

If there's a related issue:
```bash
gh issue view <number> --json milestone --jq '.milestone.title'
```

## Step 6: Create PR

```bash
gh pr create --milestone "<milestone>" --title "<title>" --body "$(cat <<'EOF'
## Summary
- <bullet points describing changes>

## Milestone
<milestone name> — <what this PR accomplishes toward the milestone>

## Related Issues
Closes #<number>

## Preflight
- [x] `mix format --check-formatted`
- [x] `mix compile --warnings-as-errors`
- [x] `mix test` (N tests, 0 failures)
- [x] `mix credo --strict`
- [x] `mix deps.unlock --check-unused`
- [x] No secrets in diff

## Test Plan
- [ ] <test checklist specific to this PR>

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
  - `docs(guide): add library integration guide`

## Branch Naming

```
feature/p2-session-genserver
feature/p4-embedded-mode
fix/port-buffer-overflow
docs/api-examples
```
