# Project Settings (inferred — no config file required)

These skills are generic and live in `~/.claudita/skills/`. They work out project-specific settings by **inference** — there is no required config file. If a project needs a specific value, note it in the project's `CLAUDE.md` (or README) and honor whatever it says.

## How each setting is resolved

- **repo** (`owner/name`) — `gh repo view --json nameWithOwner`.
- **worktree base** — `/tmp/<repo-name>` (created if missing).
- **CI command** — probe in order: `bin/ci` → `bin/rails test` / the stack's test runner. Never invent one; if unsure, ask.
- **conventions doc** — the repo-root `CLAUDE.md`, if present. It's the source of truth for architecture, testing, and workflow rules.
- **patterns skill** — `/rails-patterns` for a Rails project (`bin/rails` or a Rails `Gemfile`); otherwise none. Never assume Rails.
- **bug checklist** — the built-in `~/.claudita/skills/_shared/bug-checklist.md`, plus any checklist the project's `CLAUDE.md` points to.
- **PR body** — the built-in template (`~/.claudita/skills/mr-frond/assets/pr-body.md`).

## Linear is off by default

Linear is **not** used unless a project opts in. If the project's `CLAUDE.md` names a Linear team **and** the Linear MCP is connected, the ticket steps in `/gene` and `/mr-frond` turn on and use `[PREFIX-NN]` prefixes on commits, branches, and PR titles. Otherwise those steps are skipped and plain descriptions are used. `/linda` needs the Linear MCP; without it, say so and stop.

## Golden rule

Never hardcode a repo slug, CI command, or team name — and never block on a missing config file. Infer what you can, honor anything the project's `CLAUDE.md` specifies, and ask when a value is neither inferable nor documented.
