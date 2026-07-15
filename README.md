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
├── shell/
│   └── statusline.sh  # status line renderer
├── settings/
│   └── settings.json  # settings template (__STATUSLINE__ is filled in at install)
├── codex/
│   └── config.example.toml
└── install.sh
```

## Install

```bash
./install.sh                    # prompts for the Claude config dir (default ~/.claude)
./install.sh -c ~/.claudita     # target a custom CLAUDE_CONFIG_DIR
./install.sh -c ~/.claude -y    # non-interactive
./install.sh --no-codex         # skip Codex
```

`install.sh` symlinks the shared files into the target config dir(s). Anything it
would overwrite is backed up to `*.bak.<timestamp>` first. Re-running is safe and
idempotent.

Run it once per config dir if you keep several (e.g. `~/.claude` and `~/.claudita`).

## How Claude + Codex stay in sync

- **Claude Code** reads `CLAUDE.md`, which is just `@AGENTS.md`, so it imports the
  canonical instructions.
- **Codex** reads `AGENTS.md` directly (symlinked into `~/.codex`).

Both point at the same `AGENTS.md`, so there is **one file to edit** and zero drift.

`skills/`, `commands/`, and `settings.json` are Claude-specific — Codex has no
equivalent skills system, so only the instructions layer is shared with it.
`settings.json` is *generated* (not symlinked) because it embeds an absolute path
to `shell/statusline.sh`; per-account settings can therefore diverge safely.

## New machine

```bash
git clone <your-repo-url> ~/server/ai-config
cd ~/server/ai-config
./install.sh -c ~/.claudita
```
