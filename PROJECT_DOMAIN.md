# ai-config Domain Map

**Portable instructions and skills for Claude Code + Codex, plus Claude Code commands and hooks, installed by symlink from one source of truth.** Stack: Bash + `jq`, no build step; tests are plain shell suites under `hooks/test/`, run with `hooks/test/run_all.sh`.

**This file is the navigational index.** For full detail on any item, jump to its
`<!-- pd:* -->` anchor via the index below.

## Index
| Section | Anchor |
|---------|--------|
| How the pieces relate | pd:relationships |
| Entry points | pd:entry_points |
| Key rules and invariants | pd:business_rules |
| Instructions (AGENTS.md) | pd:instructions |
| Hooks | pd:hooks |
| Session ledger + commit tooling | pd:ledger |
| Skills and personas | pd:skills |
| Shell (statusline, Stop reporting) | pd:shell |
| Tests | pd:tests |

<!-- pd:relationships -->
## Relationship Map

```
AGENTS.md ──(CLAUDE.md is "@AGENTS.md")── Claude Code
    │        └──(symlink)──────────────── Codex ~/.codex/AGENTS.md
skills/<name>/SKILL.md ──(symlink)─────── Claude ~/.claude/skills + Codex ~/.codex/skills
    │
    │ the rules with a mechanical failure mode are backed by a hook:
    ├── persona rotation      -> hooks/session_start_persona_pick.sh + require_persona.sh
    ├── domain map first      -> hooks/session_start_domain_map.sh + require_domain_map.sh
    ├── stay on main          -> hooks/block_branch_creation.sh
    ├── own-work-only commits -> hooks/session_ledger.sh -> bin/mine, bin/commit-mine
    │                            + hooks/require_scoped_commit.sh
    ├── never discard others' -> hooks/block_discard_changes.sh
    ├── Definition of Done    -> hooks/require_dod.sh (steps 3-4 only)
    ├── no prod mutations     -> hooks/block_kamal_mutations.sh
    └── commit every session  -> nothing yet; instruction only

install.sh wires all of the above into <config dir>/settings.json (merge, never overwrite)
```

<!-- pd:entry_points -->
## Entry Points

- **`install.sh`** — the only executable a user runs directly. Symlinks instructions
  and skills into Claude Code and Codex, links Claude-only commands and agents, merges
  the hook + statusline keys into `settings.json` via `jq` (`merge_settings()`), and
  supports `--only <components>` and single-tool installs; re-running is idempotent.
- **`bin/mine`** — this session's diff / file list, from the ledger.
- **`bin/commit-mine`** — commit exactly this session's changes.
- **`hooks/test/run_all.sh`** — the whole test suite.
- **Slash commands** — `commands/fr.md`, `commands/learn.md`.
- **Skills** — `skills/<name>/SKILL.md`, invoked as `/<name>` in Claude Code and
  `$<name>` in Codex.

<!-- pd:business_rules -->
## Key Business Rules

- **`AGENTS.md` is the single source of truth**; `CLAUDE.md` is one line (`@AGENTS.md`).
  A rule that has a hook, changed in only one of the two places, is drift. Not every rule
  has one — see the relationship map for which do.
- **The commit gates advise; four hooks still deny.** `require_scoped_commit.sh` and
  `require_dod.sh` name their hazard and let the work through (`hooks/lib/advice.sh` carries
  both output shapes). `block_branch_creation.sh`, `block_kamal_mutations.sh`,
  `require_persona.sh` and `require_domain_map.sh` refuse outright.
- **`Stop` feedback must never reach the model** (`advise_user`), or it resumes the very
  turn the user is ending. `PreToolUse` feedback may (`advise_tool`).
- **Role is not provenance.** Hook notes, subagent reports and command output all wear
  `role: "user"` in the transcript, so a gate that trusts the role licenses itself off its own
  message. `GENUINE_USER_TEXT` (`hooks/lib/bash_command.sh`) is the shared filter, but only
  `require_domain_map.sh` uses it: `require_dod.sh` carries its own inline copy and
  `require_persona.sh` greps the raw transcript.
- **`settings.json` is never symlinked or overwritten** — `install.sh` merges only its own keys.
- **A commit carries only its own session's work.** `.git/index` is shared by every agent
  in the tree, so attribution is recorded as it happens by the ledger, not reconstructed.
- **Nothing discards a working tree it shares.** A linked worktree (git dir != common dir) and
  scratch space are the only exemptions `block_discard_changes.sh` grants.

<!-- pd:instructions -->
## Instructions

`AGENTS.md` — language rules, git workflow, code philosophy (DHH craftsmanship +
Hickey's "Simple Made Easy"), and working standards (Definition of Done, handing off,
blast radius, codebase navigation, round trips). `CLAUDE.md` imports it.

<!-- pd:hooks -->
## Hooks

Wired globally by `install.sh:merge_settings()`. The Bash-reading ones source
`hooks/lib/bash_command.sh`; the two that advise rather than deny source `hooks/lib/advice.sh`.

| Hook | Event | What it does |
|------|-------|--------------|
| `session_start_persona_pick.sh` | SessionStart | picks a rotating work persona |
| `session_start_domain_map.sh` | SessionStart | names this file, or asks for it |
| `require_persona.sh` | PreToolUse (Edit/Write/Bash) | denies source edits before a persona |
| `require_domain_map.sh` | PreToolUse (Grep/Glob/Bash) | denies a blind source sweep |
| `block_branch_creation.sh` | PreToolUse (Bash) | denies branch creation — stay on main |
| `block_kamal_mutations.sh` | PreToolUse (Bash) | denies Kamal prod mutations |
| `require_scoped_commit.sh` | PreToolUse (Bash) | notes a commit sweeping the shared index |
| `block_discard_changes.sh` | PreToolUse (Bash) | denies checkout/restore/reset --hard/stash/clean |
| `session_ledger.sh pre\|post` | Pre/PostToolUse | snapshots each touched file, per session |
| `ast_grep_scan.sh` | PostToolUse (Edit/Write) | structural lint, silent without `sgconfig.yml` |
| `require_dod.sh` | Stop | reports skipped Definition-of-Done steps |

`hooks/lib/bash_command.sh` holds the shared parsing every Bash gate needs:
`strip_heredoc_bodies` (a heredoc body is data, not commands), `source_write_targets`,
`git_working_dir`, `sweep_paths`, `domain_map_path`, `GIT_COMMIT_VERB`, `GENUINE_USER_TEXT`.

<!-- pd:ledger -->
## Session Ledger + Commit Tooling

`hooks/lib/ledger.sh` + `hooks/session_ledger.sh` keep, per file a session touches, an
`origin` blob (content when first touched) and a `shadow` blob (origin plus only this
session's edits). Another agent's lines sit in both and cancel out.

- `bin/mine` — this session's diff (`--files` for paths only). Contested files, where two
  sessions rewrote the same lines, are reported and never committed.
- `bin/commit-mine` — replays `origin -> shadow` onto HEAD in a *private* index
  (`GIT_INDEX_FILE`), then moves the ref with a compare-and-swap. `--dry-run` prints what
  would land and what is skipped. HEAD moving underneath is absorbed (3-way merge).

<!-- pd:skills -->
## Skills and Personas

`skills/<name>/SKILL.md`, symlinked file-by-file into both tool config dirs.

- **Work personas (rotated per session):** `bob`, `tina`, `louise` — feature/bugfix work.
- **`gene`** — fast commit to local `main`. No PR, no push. Reads the session ledger,
  runs the Definition-of-Done spot-check, optionally logs a Linear ticket.
- **`mr-frond`** — packages uncommitted work into a PR on a worktree.
- **`teddy`** — fixes PR review feedback, rebases stale PRs.
- **`mr-fischoeder`** — fresh-eyes review of the working-tree diff or an open PR.
- **`linda`** — Linear tickets only.
- **`project-domain`** — this map's own skill: bootstrap and keep it filled.
- **`rails-patterns`** — Campfire/Basecamp Rails reference, with `references/*.md`.
- **`_shared/`** — `bug-checklist.md` and `project-config.md`, referenced by every persona.
- **`agents/explore.md`** — read-only survey subagent.

<!-- pd:shell -->
## Shell

- `shell/statusline.sh` — the status line renderer (`statusLine` in settings.json).
- `shell/config_status.sh` — Stop hook: reports uncommitted changes *in this repo*.

<!-- pd:tests -->
## Tests

`hooks/test/` — suites for `install`, `block_branch_creation`, `block_discard_changes`, `require_dod`,
`require_domain_map`, `require_persona`, `require_scoped_commit`, plus `session_ledger_test.sh`
for attribution. `block_kamal_mutations`, `ast_grep_scan` and the two `session_start_*` hooks
have none. `pretooluse_helper.sh` is the shared harness (set `HOOK` and `T`, then
`expect_*` / `report`). Run everything with `hooks/test/run_all.sh`.
