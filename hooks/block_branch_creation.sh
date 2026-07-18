#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny `git checkout -b` / `git switch -c`. The global git
# rule is "always work directly on main" — branches are only created deliberately by
# the PR-packaging (/mr-frond, worktree-based) and PR-fix (/teddy) flows, never as a
# side effect of implementation work. Wired globally by install.sh (see merge_settings).
#
set -u

CMD="$(jq -r '.tool_input.command // empty')"

if printf '%s' "$CMD" | grep -qE '(^|[[:space:]|;&])(git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c))[[:space:]]'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Git rule (AGENTS.md): always work on main — no feature branches unless explicitly asked. Use /mr-frond (worktree-based) to package a PR, or /teddy to fix an existing PR branch."}}
JSON
fi
