#!/usr/bin/env bash
#
# PreToolUse hook: deny source edits until a work persona has been invoked in this
# session. Passes on either form of invocation:
#   - the model calling the Skill tool        -> "skill":"bob" / "commandName":"bob"
#   - the user typing the slash command        -> <command-name>/bob</command-name>
#
# Wired on Edit|Write|MultiEdit *and* on Bash, because auto mode writes most files
# through Bash (see hooks/lib/bash_command.sh). Either way only source writes are
# gated; docs, reads and every other command pass untouched.
#
# Wired globally by install.sh (see merge_settings).
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

PERSONAS='bob|tina|louise|teddy|gene|mr-frond'

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# One policy, whichever tool the model reached for: writing source needs a persona,
# writing docs does not. A Bash redirect and an Edit call to the same path must not
# get opposite answers.
if [ -n "$CMD" ]; then
  [ -n "$(printf '%s\n' "$CMD" | source_write_targets)" ] || exit 0
else
  FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
  [ -n "$FILE" ] && is_source_path "$FILE" || exit 0
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] \
   && grep -qE "\"(skill|commandName)\":\"($PERSONAS)\"|<command-name>/($PERSONAS)" "$TRANSCRIPT"; then
  exit 0
fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Invoke a work persona (/bob, /tina, or /louise) before editing files. Rotate between them across sessions."}}
JSON
