#!/usr/bin/env bash
#
# PreToolUse hook (Edit|Write|MultiEdit): deny file edits until a work persona has
# been invoked in this session. Passes on either form of invocation:
#   - the model calling the Skill tool        -> "skill":"bob" / "commandName":"bob"
#   - the user typing the slash command        -> <command-name>/bob</command-name>
# Wired globally by install.sh (see merge_settings).
#
set -u

PERSONAS='bob|tina|louise|teddy|gene|mr-frond'

INPUT="$(cat)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] \
   && grep -qE "\"(skill|commandName)\":\"($PERSONAS)\"|<command-name>/($PERSONAS)" "$TRANSCRIPT"; then
  exit 0
fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Invoke a work persona (/bob, /tina, or /louise) before editing files. Rotate between them across sessions."}}
JSON
