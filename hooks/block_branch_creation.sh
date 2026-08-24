#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny `git checkout -b` / `git switch -c`. The global git
# rule is "always work directly on main" — branches are only created deliberately by
# the PR-packaging (/mr-frond, worktree-based) and PR-fix (/teddy) flows, never as a
# side effect of implementation work. Wired globally by install.sh (see merge_settings).
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

CMD="$(jq -r '.tool_input.command // empty')"
CMD="$(printf '%s\n' "$CMD" | strip_heredoc_bodies)"

# Creating a branch has many spellings: a short or long create flag anywhere in the
# argument list (not just first), `git branch <name>`, and `git worktree add -b`.
# Inspection and deletion stay free — but `--force` on `git branch` creates one too.
CREATE='git[[:space:]]+(checkout|switch)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*[bBcC]|--create|--force-create)([[:space:]]|$)'
CREATE="$CREATE"'|git[[:space:]]+branch[[:space:]]+([^-[:space:]]|(-f|--force)([[:space:]]|$))'
CREATE="$CREATE"'|git[[:space:]]+worktree[[:space:]]+add([[:space:]]+[^-[:space:]][^[:space:]]*)*[[:space:]]+(-[bB]|--create)([[:space:]]|$)'

if printf '%s' "$CMD" | grep -qE "(^|[[:space:]|;&])($CREATE)"; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Git rule (AGENTS.md): always work on main — no feature branches unless explicitly asked. Use /mr-frond (worktree-based) to package a PR, or /teddy to fix an existing PR branch."}}
JSON
fi
