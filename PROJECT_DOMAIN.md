# ai-config domain map

Portable Claude Code and Codex instructions, skills, and hooks. Bash 3.2-compatible
shell, Git, jq, and Python 3; no build step.

| Topic | Anchor |
|---|---|
| Installation and instructions | pd:installation |
| Skills | pd:skills |
| Hooks and commits | pd:hooks |
| Validation | pd:validation |

<!-- pd:installation -->
## Installation and instructions

- `install.sh` links shared resources and merges only owned hook registrations.
- `instructions/AGENTS.md` supplies global preferences to both hosts;
  `instructions/CLAUDE.md` imports the neighboring AGENTS.md for Claude.
- Root `AGENTS.md` and `CLAUDE.md` describe this repository only, avoiding a second
  copy of global preferences when working here.
- Host configuration and unrelated permission choices must survive installation.
- `README.md` documents flags, installation, hook trust, and workflow limitations.
- `codex/config.example.toml` is optional and never overwrites live model settings.

<!-- pd:skills -->
## Skills

`skills/<name>/SKILL.md` is the entrypoint in either host. References resolve relative
to that directory, including `../_shared/`.

- `bob`, `tina`, `louise`: optional implementation voices.
- `gene`: scoped local commit; push only on explicit request; truthful ticket state.
- `mr-frond`: package a recorded session delta into a PR.
- `teddy`: address actionable PR feedback and conflicts, stopping for external reviews.
- `mr-fischoeder`: scoped review with concrete failure evidence.
- `project-domain`: consult or maintain a concise map when useful.
- `rails-patterns`: conditional references for Basecamp-style Rails conventions.
- `_shared/bug-checklist.md`: universal review questions; specialized rules stay scoped.
- `agents/explore.md`: Claude read-only survey, returning conclusions and citations.

<!-- pd:hooks -->
## Hooks and commits

- `hooks/block_branch_creation.sh`, `block_discard_changes.sh`, and
  `block_kamal_mutations.sh`: Claude action guards.
- `hooks/require_scoped_commit.sh`: advisory note for shared-index commits.
- `hooks/session_start_domain_map.sh`: optional map location hint, never bootstrap demand.
- `hooks/ast_grep_scan.sh`: structural lint when a project has `sgconfig.yml`.
- `hooks/require_persona.sh`, `require_domain_map.sh`, `require_dod.sh`,
  `session_start_persona_pick.sh`, and `shell/config_status.sh`: retired compatibility
  entrypoints; installation removes their registrations.
- `hooks/session_ledger.sh`, `hooks/lib/ledger_capture.py`, `hooks/lib/ledger.sh`:
  reconstruct explicit edits, verify outcomes, and lock per-session state. Shell
  mutations and unsupported patch forms are not automatically attributed. Codex
  UserPromptSubmit supplies the session ID as context for explicit ledger commands;
  PreToolUse does not change command permissions.
- `bin/mine`: inspect the session record; `bin/commit-mine`: private-index replay and
  compare-and-swap commit. Neither dirty filenames nor command-duration snapshots
  establish ownership. Unsupported or ambiguous edits must not be committed as verified.
- `hooks/lib/bash_command.sh`: shared command/path parsing for action guards.
- `shell/statusline.sh`: optional Claude display.

Preserve other writers' files and index. Serialize overlapping writes; the commit
index is private, but the working tree is shared. Hook protocols and coverage differ
between hosts, so verify real payload shapes before changing installation or recording.

<!-- pd:validation -->
## Validation

`hooks/test/*_test.sh` suites run in temporary repositories/config directories.
Run the affected suite while iterating, then `bash hooks/test/run_all.sh` for shared
infrastructure changes. Installation tests cover preservation, idempotence, and
paths requiring quoting. Ledger tests cover attribution and conservative failures.
