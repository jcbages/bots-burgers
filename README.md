# ai-config

Portable, version-controlled configuration for AI coding assistants — shared across
machines and across tools (Claude Code + Codex) from a single source of truth.

Clone it on a new laptop, run `./install.sh`, and your instructions, skills,
commands, and status line are wired back into place.

## Layout

```
ai-config/
├── AGENTS.md          # canonical instructions (the single source of truth)
├── CLAUDE.md          # one line: "@AGENTS.md" — Claude imports AGENTS.md
├── commands/          # Claude slash commands (fr, learn, ...)
├── skills/            # shared Claude Code + Codex skills (characters, rails-patterns, ...)
├── agents/            # Claude subagents (explore: read-only codebase survey)
├── hooks/             # global hooks wired into Claude settings + Codex hooks.json
│   ├── session_start_persona_pick.sh  # SessionStart: pick a persona to invoke
│   ├── session_start_domain_map.sh    # SessionStart: point at PROJECT_DOMAIN.md (or bootstrap it)
│   ├── require_persona.sh             # PreToolUse (+Bash): deny source edits until a persona is invoked
│   ├── block_branch_creation.sh      # PreToolUse (Bash): stay on main, no feature branches
│   ├── require_scoped_commit.sh      # PreToolUse (Bash): note a commit that sweeps the shared index
│   ├── session_ledger.sh             # Pre/PostToolUse: record this session's own changes
│   ├── block_kamal_mutations.sh      # PreToolUse (Bash): no Kamal prod mutations
│   ├── require_domain_map.sh         # PreToolUse (+Grep|Glob): deny a source-tree sweep until /project-domain runs
│   ├── ast_grep_scan.sh              # PostToolUse: structural lint of the written file
│   ├── require_dod.sh                # Stop: report skipped Definition-of-Done steps
│   ├── lib/bash_command.sh           # shared: what a Bash command writes, minus heredoc bodies
│   └── test/                         # a suite per gated behaviour; run hooks/test/run_all.sh
├── shell/
│   ├── statusline.sh  # status line renderer
│   └── config_status.sh  # Stop: report uncommitted config changes (never commits)
├── codex/
│   └── config.example.toml
└── install.sh
```

## Install

```bash
./install.sh                      # prompts for the Claude config dir (default ~/.claude)
./install.sh -c ~/.claudita       # target a custom CLAUDE_CONFIG_DIR
./install.sh -c ~/.claude -y      # non-interactive
./install.sh --no-codex           # skip Codex
./install.sh --only skills        # install skills into Claude Code and Codex
./install.sh --only skills --no-claude  # install skills into Codex only
./install.sh --only skills,commands   # ...or a few
```

`install.sh` symlinks the shared files into the target config dir(s). Skill
directories are linked **file by file** into both tools, so existing entries such
as Codex's `.system` skills are left in place. Claude-only `commands` and `agents`
are linked the same way. A different same-named entry is backed up to
`*.bak.<timestamp>`; an existing link to the same source is left unchanged.
Re-running is safe and idempotent.

Use `--only` to install a subset. Valid components:
`instructions`, `commands`, `skills`, `agents`, `settings`, `codex`
(`settings` wires Claude's statusline and hooks, plus Codex's session ledger hooks).
Without `--only`, everything is installed into each enabled tool.

Use `--no-claude` or `--no-codex` to install into just one tool. Run it once per
Claude config dir if you keep several (e.g. `~/.claude` and `~/.claudita`).

## How Claude + Codex stay in sync

- **Claude Code** reads `CLAUDE.md`, which is just `@AGENTS.md`, so it imports the
  canonical instructions.
- **Codex** reads `AGENTS.md` directly (symlinked into `~/.codex`) and discovers
  skills from `~/.codex/skills`.

Both tools use the same `AGENTS.md` and skill sources, so there is **one source to
edit** and zero drift.

Codex skills are discovered from each skill's `SKILL.md` and can be selected from
their descriptions; invoke one explicitly with `$skill-name`. Claude Code skills
use `/skill-name`. Commands and subagents remain Claude Code-specific in this installer.

`settings.json` and Codex `hooks.json` are never symlinked or overwritten. They hold
account-specific settings and hooks; `install.sh` **merges** only the entries it owns
via `jq`, leaving every other key untouched:

- `statusLine` → `shell/statusline.sh`
- `hooks.Stop` → `hooks/require_dod.sh` (reports skipped Definition-of-Done steps) + `shell/config_status.sh` (report uncommitted config changes)
- `hooks.SessionStart` → `hooks/session_start_persona_pick.sh` (pick a persona for the session) + `hooks/session_start_domain_map.sh` (name the project's domain map, or ask for it to be bootstrapped)
- `hooks.PreToolUse` → `hooks/require_persona.sh` (deny source edits until a persona is invoked); on `Bash`, `require_persona.sh` + `block_branch_creation.sh` + `require_scoped_commit.sh` + `block_kamal_mutations.sh` + `require_domain_map.sh`; on `Grep`/`Glob`, `require_domain_map.sh` (deny a source-tree sweep until `/project-domain` runs)
- `hooks.PostToolUse` → `hooks/ast_grep_scan.sh` (structural lint of the written file)

The status line and hooks point at absolute paths inside this repo.

Codex lifecycle hooks are merged into the selected Codex config directory's
`hooks.json`, preserving unrelated
entries. They record this session's file changes before and after `Bash` and
`apply_patch` tools, so `$gene` can use `bin/mine` and `bin/commit-mine` in Codex too.
Codex asks you to review and trust newly installed hooks before they run; open
`/hooks` in Codex and trust the session ledger hooks, then start a new session.

## New machine

```bash
git clone <your-repo-url> ~/server/ai-config
cd ~/server/ai-config
./install.sh -c ~/.claudita
```
