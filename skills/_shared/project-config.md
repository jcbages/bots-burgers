# Project Config (preamble for shared skills)

These skills are generic and live in `~/.claudita/skills/`. Everything project-specific — repo, Linear team, ticket prefix, CI command — is read from a per-project config file, never hardcoded.

## Step 0 (do this before anything else)

Read `.claude/project.yml` at the repo root. **The file is optional** — every value is either inferable or promptable. Use it to pin the things that are expensive to guess wrong (repo slug, CI command); let the rest be inferred. If a value you need is neither in config nor cheaply derivable, ask — never assume.

## Schema (all keys optional)

```yaml
# .claude/project.yml — consumed by generic ~/.claudita skills. All keys optional.
repo: owner/name              # GitHub slug (for gh). Inferred from `gh repo view` if absent.
worktree_base: /tmp/app       # where worktrees are created. Defaults to /tmp/app.

linear:                       # OPTIONAL — omit the whole block to disable Linear entirely.
  team: TeamName              # inferred from the MCP if a single team is connected
  ticket_prefix: KEY          # -> "[KEY-123]"
  users:                      # username -> Linear email (used by /linda)
    someuser: someuser@example.com

ci:
  command: bin/ci             # full CI gate
  test_command: bin/rails test

pr:
  body_template: null         # optional path to a PR body template; null = built-in

docs:
  conventions: CLAUDE.md      # project conventions doc
  domain_map: null            # optional domain map (e.g. DOMAIN.md); null if none
  patterns_skill: rails-patterns   # patterns skill to reference (or null)
  bug_checklist: builtin      # "builtin" = ~/.claudita/skills/_shared/bug-checklist.md,
                              # or a path to the project's own checklist
```

## What must be set vs what is inferred

**Nothing is strictly required** — but pin the values that are costly to get wrong.

| Value | If absent | Advice |
|---|---|---|
| `repo` | derived from `gh repo view --json nameWithOwner` (offer to write it back) | pin it |
| `worktree_base` | defaults to `/tmp/app` | leave default |
| `ci.command` / `test_command` | probe `bin/ci` → `bin/rails test` → detect the stack's runner; never invent one | pin it |
| `linear:` block | **Linear is disabled** — ticket steps are skipped | pin only if you use Linear |
| `linear.team` (block present) | infer the single connected team from the MCP; else ask | optional |
| `linear.users` | resolve via the Linear MCP `list_users`; else ask | optional |
| `pr.body_template` | built-in template | optional |
| `docs.conventions` | no conventions doc is read | pin if you have one |
| `docs.domain_map` / `patterns_skill` | not referenced | optional |
| `docs.bug_checklist` | `builtin` checklist | optional |

## Linear is optional

If the `linear:` block is absent **or** the Linear MCP is not connected, treat Linear as unavailable:

- **/gene, /mr-frond** — skip the ticket step and drop the `[<PREFIX>-XX]` prefix from commits, branches, and PR titles; use a plain imperative description instead. Everything else runs normally.
- **/linda** — Linda's whole job is Linear. Without the MCP connected she can't work: say so plainly and stop. With the MCP connected but no `linear.team`, infer the single connected team (or ask).

## Golden rule

Never hardcode a repo slug, team name, ticket prefix, or CI command. If a value isn't in config and isn't cheaply derivable, ask — don't assume.
