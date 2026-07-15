# Project Config (MANDATORY preamble for shared skills)

These skills are generic and live in `~/.claudita/skills/`. Everything project-specific — repo, Linear team, ticket prefix, CI command, PR authors — is read from a per-project config file. Never hardcode those values.

## Step 0 (do this before anything else)

Read `.claude/project.yml` at the repo root.

**If it is missing**, STOP and tell the user:

> "I need a `.claude/project.yml` to run this skill. Want me to scaffold one? Here's the schema:" — then show the schema below and wait. Do not guess the repo, team, or CI command.

## Schema

```yaml
# .claude/project.yml — consumed by generic ~/.claudita skills
repo: owner/name              # GitHub slug (for gh)
worktree_base: /tmp/app       # where worktrees are created

linear:
  team: TeamName
  ticket_prefix: KEY          # -> "[KEY-123]"
  users:                      # username -> Linear email (used by /linda)
    someuser: someuser@example.com

ci:
  command: bin/ci             # full CI gate
  test_command: bin/rails test

pr:
  authors: [user_a, user_b]   # /teddy only touches PRs by these authors
  body_template: null         # optional path to a PR body template; null = built-in

docs:
  conventions: CLAUDE.md      # project conventions doc
  domain_map: null            # optional domain map (e.g. DOMAIN.md); null if none
  patterns_skill: rails-patterns   # patterns skill to reference (or null)
  bug_checklist: builtin      # "builtin" = ~/.claudita/skills/_shared/bug-checklist.md,
                              # or a path to the project's own checklist
```

## Resolving values

- **repo / worktree_base**: from config. If `repo` is absent, derive from `gh repo view --json nameWithOwner` and offer to write it back.
- **linear.team / ticket_prefix**: from config. If absent and the Linear MCP is connected with a single team, use it; otherwise ask.
- **linear.users**: from config. If a needed username is missing, resolve via the Linear MCP `list_users` before falling back to asking.
- **ci / test_command**: from config. If absent, probe: `bin/ci` → `bin/rails test` → detect the stack's test runner. Never invent one.
- **pr.authors**: from config. If absent, default to the current user only.
- **docs.bug_checklist**: `builtin` → `~/.claudita/skills/_shared/bug-checklist.md`; also read the project's own checklist if one is configured.
- **docs.patterns_skill / domain_map**: reference only if set. Never assume a Rails project.

## Golden rule

Never hardcode a repo slug, team name, ticket prefix, CI command, or author list. If a value isn't in config and isn't cheaply derivable, ask — don't assume.
