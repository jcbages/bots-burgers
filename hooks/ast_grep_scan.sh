#!/usr/bin/env bash
#
# PostToolUse hook (Edit|Write): run ast-grep's project ruleset against the file
# that was just written, surfacing structural lint findings inline. Silent in projects
# with no `sgconfig.yml` — including the "install ast-grep" nudge, which otherwise
# fires on every single write in every project that would never use it.
# Wired globally by install.sh (see merge_settings).
#
set -u

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)}"
[ -n "$PROJECT" ] && { [ -f "$PROJECT/sgconfig.yml" ] || [ -f "$PROJECT/sgconfig.yaml" ]; } || exit 0

if ! command -v ast-grep &>/dev/null; then
  echo '[warning] this project has an sgconfig.yml but ast-grep is not installed. Run: brew install ast-grep'
  exit 0
fi

ast-grep scan "$FILE" 2>/dev/null || true
