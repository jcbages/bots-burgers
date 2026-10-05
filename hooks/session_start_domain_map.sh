#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/bash_command.sh"
CWD="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty')}"
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
MAP="$(domain_map_path "$ROOT")"
[ -n "$MAP" ] || exit 0
jq -n --arg context "Optional codebase orientation: $MAP. Consult it when useful; verify relevant paths against the current code." \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$context}}'
