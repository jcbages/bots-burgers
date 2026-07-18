#!/usr/bin/env bash
#
# PostToolUse hook (Edit|Write): run ast-grep's project ruleset against the file
# that was just written, surfacing structural lint findings inline. No-op when
# ast-grep isn't installed or the project has no `sgconfig.yml` — safe everywhere.
# Wired globally by install.sh (see merge_settings).
#
set -u

if ! command -v ast-grep &>/dev/null; then
  echo '[warning] ast-grep is not installed. Run: brew install ast-grep'
  exit 0
fi

FILE="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

ast-grep scan "$FILE" 2>/dev/null || true
