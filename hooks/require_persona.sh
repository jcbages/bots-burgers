#!/usr/bin/env bash
#
# PreToolUse hook (Edit|Write|MultiEdit): deny file edits until a work persona has
# been invoked in this session. Passes once the transcript shows one of the editing
# personas was picked. Wired globally by install.sh (see merge_settings).
#
set -u

INPUT="$(cat)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] \
   && grep -qE '"(skill|commandName)":"(bob|tina|louise|teddy|gene|mr-frond)"' "$TRANSCRIPT"; then
  exit 0
fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Invoke a work persona (/bob, /tina, or /louise) before editing files. Rotate between them across sessions."}}
JSON
