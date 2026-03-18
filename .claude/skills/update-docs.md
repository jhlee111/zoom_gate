---
name: update-docs
description: Update project documentation — comprehensive guide for all doc types
user_invocable: true
---

# Update Documentation Skill for ZoomGate

## Documentation Map

All documentation types and where they live:

| Type | Location | When to Update |
|------|----------|----------------|
| **ModuleDoc** | `@moduledoc` / `@doc` in source | Module behavior or public API changes |
| **README** | `README.md` | New features, deployment modes, quick start changes |
| **CHANGELOG** | `CHANGELOG.md` | Every release (created by `/release` skill) |
| **CLAUDE.md** | `CLAUDE.md` | Project structure, conventions, new modules/milestones |
| **Usage Rules** | `usage-rules.md` | API contract changes for AI agent consumers |
| **ExDoc Guides** | `guides/*.md` | New guides, updated workflows, architecture changes |
| **ADR** | `docs/adr/NNNN-<title>.md` | Significant architectural decisions |
| **Master Plan** | `docs/plan.md` | Milestone planning, roadmap changes |
| **Internal Notes** | `docs/internal/*.md` | Research findings, protocol analysis, SDK notes |
| **OpenAPI Spec** | `lib/zoom_gate/api_spec.ex` | REST API endpoint changes |
| **GitHub Issues** | github.com/jhlee111/zoom_gate/issues | Task tracking, research findings |

---

## 1. Code Docs (`@moduledoc` / `@doc`)

The Elixir-native way. Discoverable via `h Module` in IEx and rendered by ExDoc.

- `@moduledoc` on ALL public modules
- `@doc` on ALL public functions
- Include typespecs (`@spec`) for public functions
- Update when module behavior or function signatures change

## 2. README.md

Project root. First thing users see.

Update when:
- New features or API endpoints added
- Deployment instructions change
- New deployment mode (standalone/embedded)
- Configuration options change

## 3. CHANGELOG.md

[Keep a Changelog](https://keepachangelog.com/) format. Updated during `/release`.

```markdown
## [0.x.y] - YYYY-MM-DD

### Added
### Fixed
### Changed
### Removed
```

## 4. CLAUDE.md

Instructions for Claude Code. Project structure and conventions.

Update when:
- New modules or directories added
- Conventions change (git, code style)
- New milestones or related projects
- Protocol or architecture changes

## 5. usage-rules.md

Machine-readable API contract for AI agents consuming ZoomGate.

Update when:
- Public API functions change
- Event payload structures change
- New commands or events added
- Configuration options change

## 6. ExDoc Guides (`guides/*.md`)

Rendered in ExDoc at `/docs/`. Must be listed in `mix.exs` → `docs()` → `extras`.

Current guides:
- `guides/session-lifecycle.md` — State machine and lifecycle
- `guides/authentication.md` — API key auth, Zoom credentials
- `guides/webhooks.md` — Webhook delivery and retry
- `guides/error-reference.md` — Error codes and handling
- `guides/library-integration.md` — Embedded mode setup

When adding a new guide:
```elixir
# mix.exs → docs() → extras
extras: [
  "README.md",
  "guides/session-lifecycle.md",
  "guides/authentication.md",
  "guides/webhooks.md",
  "guides/error-reference.md",
  "guides/library-integration.md",
  "guides/new-guide.md"          # ← add here
]
```

Verify with `mix docs` — check for broken links and rendering.

## 7. ADR (Architecture Decision Records)

Location: `docs/adr/NNNN-<title>.md` (create dir if needed)

Use for significant, hard-to-reverse decisions. Format:

```markdown
# NNNN: Decision Title

## Status
Accepted | Superseded by NNNN

## Context
Why this decision was needed.

## Decision
What we decided.

## Consequences
What follows from this decision.
```

Examples of ADR-worthy decisions:
- Port vs NIF for native SDK
- Pure Elixir WebSocket vs C++ SDK
- Per-meeting GenServer architecture
- Three-layer API design

## 8. Master Plan (`docs/plan.md`)

Roadmap and milestone planning. Create if needed.

Update when:
- Milestones are added, reordered, or completed
- Major scope changes
- Timeline shifts

## 9. Internal Notes (`docs/internal/*.md`)

Research, protocol analysis, SDK investigation notes. Not published in ExDoc.

Examples:
- `docs/internal/rwg-protocol.md` — RWG WebSocket reverse engineering
- `docs/internal/sdk-analysis.md` — Zoom SDK capability matrix

## 10. OpenAPI Spec

Defined in `lib/zoom_gate/api_spec.ex` using `OpenApiSpex`.

Update when REST API endpoints change. Verify with `mix docs`.

## 11. GitHub Issues & Milestones

```bash
# Check open issues
gh issue list

# Filter by milestone
gh issue list --milestone "P2: Core OTP"

# Close issue with comment
gh issue close <number> --comment "Completed in <commit/PR>"

# Check milestone progress
gh api repos/jhlee111/zoom_gate/milestones --jq '.[] | "\(.title): \(.open_issues) open / \(.closed_issues) closed"'

# Close completed milestone
gh api repos/jhlee111/zoom_gate/milestones/<N> -X PATCH -f state=closed
```

---

## After Completing Work — Checklist

1. **Update `@moduledoc` / `@doc`** if module behavior changed
2. **Update `README.md`** if public API or deployment changed
3. **Update `usage-rules.md`** if API contract changed
4. **Update `CLAUDE.md`** if structure or conventions changed
5. **Add/update ExDoc guide** if workflow documentation needed
6. **Write ADR** if an architectural decision was made
7. **Close related GitHub issue** with summary comment
8. **Check milestone progress** — close milestone if all issues done
9. **Run `mix docs`** to verify documentation renders correctly
