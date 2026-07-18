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
├── commands/          # Claude slash commands (eng, learn, ...)
├── skills/            # Claude skills (characters, rails-patterns, ...)
├── agents/            # Claude subagents (empty for now)
├── hooks/             # global hooks wired into settings.json
│   ├── session_start_persona_pick.sh  # SessionStart: pick a persona to invoke
│   ├── require_persona.sh             # PreToolUse: deny edits until a persona is invoked
│   ├── block_branch_creation.sh      # PreToolUse (Bash): stay on main, no feature branches
│   ├── block_kamal_mutations.sh      # PreToolUse (Bash): no Kamal prod mutations
│   ├── ast_grep_scan.sh              # PostToolUse: structural lint of the written file
│   └── require_dod.sh                # Stop: Definition-of-Done gate after source edits
├── shell/
│   ├── statusline.sh  # status line renderer
│   └── sync.sh        # Stop: auto-commit config changes
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
./install.sh --only skills        # install only one component
./install.sh --only skills,commands   # ...or a few
```

`install.sh` symlinks the shared files into the target config dir(s). Directory
components (`skills`, `commands`, `agents`) are linked **file by file**, so any
skills/commands you already keep in the target dir are left in place — only a
same-named entry is touched, and that is backed up to `*.bak.<timestamp>` first.
Re-running is safe and idempotent.

Use `--only` to install a subset. Valid components:
`instructions`, `commands`, `skills`, `agents`, `settings`, `codex`
(`settings` also wires the statusline + the Stop/SessionStart/PreToolUse/PostToolUse
hooks). Without `--only`,
everything is installed.

Run it once per config dir if you keep several (e.g. `~/.claude` and `~/.claudita`).

## How Claude + Codex stay in sync

- **Claude Code** reads `CLAUDE.md`, which is just `@AGENTS.md`, so it imports the
  canonical instructions.
- **Codex** reads `AGENTS.md` directly (symlinked into `~/.codex`).

Both point at the same `AGENTS.md`, so there is **one file to edit** and zero drift.

`skills/` and `commands/` are Claude-specific — Codex has no equivalent skills
system, so only the instructions layer is shared with it.

`settings.json` is never symlinked or overwritten: it holds account-specific keys
(model, permissions, theme, ...). `install.sh` **merges** only the keys it owns into
your existing file via `jq`, leaving every other key untouched:

- `statusLine` → `shell/statusline.sh`
- `hooks.Stop` → `hooks/require_dod.sh` (Definition-of-Done gate) + `shell/sync.sh` (auto-commit config changes)
- `hooks.SessionStart` → `hooks/session_start_persona_pick.sh` (pick a persona for the session)
- `hooks.PreToolUse` → `hooks/require_persona.sh` (deny edits until a persona is invoked); on `Bash`, `block_branch_creation.sh` + `block_kamal_mutations.sh`
- `hooks.PostToolUse` → `hooks/ast_grep_scan.sh` (structural lint of the written file)

The status line and hooks point at absolute paths inside this repo.

## New machine

```bash
git clone <your-repo-url> ~/server/ai-config
cd ~/server/ai-config
./install.sh -c ~/.claudita
```
