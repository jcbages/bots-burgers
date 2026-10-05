# ai-config

Shared instructions and skills for Claude Code and Codex, with a portable installer
and local hooks for protecting shared work.

## Install

Requires Bash, Git, `jq`, and Python 3. Run from a checkout you intend to keep:

```bash
./install.sh -y                         # ~/.claude and ~/.codex
./install.sh -c ~/.claude -y             # explicit Claude directory
./install.sh --only skills              # skills only
./install.sh --no-claude --only skills   # Codex skills only
./install.sh --no-codex -c ~/.claudita -y # alternate Claude profile
```

`--codex-dir DIR` selects another Codex config directory. `--only` accepts a
comma-separated list of `instructions,commands,skills,agents,settings,codex`.
Re-running installation is idempotent. Different existing link destinations are
backed up before replacement. Unrelated hooks, settings, and permission choices
are preserved; only this repository's hook registrations are replaced.

Start a new session after installing. Codex requires trust for new or changed hook
definitions: inspect `/hooks` and trust the entries from this checkout. The installer
never bypasses trust or changes your model, provider, or approval policy.

## What loads

| Path | Purpose |
|---|---|
| `instructions/AGENTS.md` | Shared user preferences installed as each host's global AGENTS.md |
| `instructions/CLAUDE.md` | Global Claude wrapper importing its neighboring AGENTS.md |
| `AGENTS.md`, `CLAUDE.md` | Instructions specific to working on this repository |
| `skills/*/SKILL.md` | Task-specific workflows; descriptions are concise, details load on demand |
| `skills/_shared/` | Small shared settings and review references |
| `agents/explore.md` | Claude read-only survey agent |
| `commands/` | Claude language commands |
| `hooks/`, `bin/` | Hook handlers and scoped commit tools |
| `shell/statusline.sh` | Optional Claude status line |
| `PROJECT_DOMAIN.md` | Navigation for this repository |

Both hosts receive the same skill directories through symlinks. Use `$gene` in
Codex and `/gene` in Claude Code; other skill names follow the same convention.
Characters are optional and continue a supplied task immediately. Artwork is opt-in.

## Workflow

Use focused context and verification appropriate to the change. Domain maps help
with unfamiliar code but are not prerequisites for searching or editing. Review
changed contracts and plausible failures; expand context when needed. Independent
review and broad tests are appropriate for substantial or risky changes, rather
than every small edit. Skill references resolve relative to their own directory.

Local commits remain the default handoff. Pushes require an explicit request.
Tickets are marked Done only when their acceptance criteria are met and the work
has landed. PR workflows process actionable revisions once and stop while awaiting
external reviews. Existing project architecture takes precedence over style examples.

## Hooks and ownership

Claude retains protections for destructive Git operations, branch creation, and
production Kamal mutations, plus scoped-commit advice and project-configured
structural lint. A SessionStart hint points at an existing domain map. Retired
persona, navigation, and completion gates are removed during installation; their
legacy scripts are harmless for sessions holding old settings.

Codex uses its own hook configuration and permission system. The installer keeps
host-specific wiring separate. Hooks supplement permissions; they are not a sandbox.
Codex's `UserPromptSubmit` hook supplies the session ID in model context for explicit
`LEDGER_SESSION=...` prefixes when invoking `bin/mine` or `bin/commit-mine`; tool
approval behavior is unchanged.

The ledger reconstructs Claude `Edit`/`Write` and unambiguous Codex `apply_patch`
operations from their explicit inputs, then checks the actual result. Mismatches
are quarantined. Shell mutations, symlink writes, and unsupported or ambiguous
patch forms are not automatically attributed. Legacy snapshot records are unverified.
Shell reads and tests do not scan or hash the working tree for attribution. Inspect
`bin/mine` before `bin/commit-mine --dry-run`; ambiguous or unsupported edits require
an independently recorded session patch or proven ownership of complete file changes.
Do not infer ownership from the current working-tree diff. Serialize overlapping
writers even when a ledger is available.

`bin/commit-mine` builds a commit through a private index and moves HEAD with a
compare-and-swap. It does not modify the shared index. That index may consequently
lag behind HEAD; do not interpret its inverse staged diff as new work or commit it
wholesale. The working tree and other sessions' staged changes are preserved.

## Validation

```bash
bash hooks/test/run_all.sh
codex doctor --summary
claude doctor
```

The test suites use temporary repositories and configuration directories. They
exercise installation, retired gates, destructive-operation guards, and attribution
failures without changing your real host configuration. Validate installer changes
there before running installation against real profiles.
