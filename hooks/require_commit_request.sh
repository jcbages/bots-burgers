#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny `git commit` unless the user asked for it *since the
# last commit*. Consent is per-commit, not per-session — one "commit this" used to
# license every commit for the rest of the session (24 in one measured session).
# Committing is the user's call and the moment they want a summary, so the denial
# hands back the handoff report instead (see AGENTS.md "Handing off").
# Wired globally by install.sh (see merge_settings).
#
set -u

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Only gate commits. Amend/fixup count; everything else in git is free.
printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Transcript is JSONL in chronological order, so line numbers order the events.
# A commit tool call: one line carrying both the Bash tool_use and the command.
LAST_COMMIT="$(grep -nE '"name":"Bash"' "$TRANSCRIPT" | grep -E 'git +commit' | tail -1 | cut -d: -f1)"

# Genuine user intent. Role is not provenance: hook feedback, subagent reports,
# system reminders and this hook's own denial are all stored with role "user" —
# and the denial necessarily contains the word "commit", so it must be excluded or
# the gate licenses itself.
INTENT="$(jq -rR 'fromjson? // empty
    | (input_line_number|tostring) as $n
    | select(.message.role=="user" and .isMeta != true)
    | ( if (.message.content|type)=="string" then .message.content
        else ([.message.content[]? | select(.type=="text") | .text] | join("\n")) end )
    | select(test("^<(task-notification|command-message|local-command-|system-reminder)") | not)
    | select(test("Explicit-commit gate") | not)
    | select(test("(?i)(\\bcommit\\b|\\bamend\\b|/gene\\b|\\bship it\\b|\\bland (it|this)\\b)"))
    | $n' "$TRANSCRIPT" 2>/dev/null | tail -1)"

[ -n "$LAST_COMMIT" ] || LAST_COMMIT=0
[ -n "$INTENT" ] || INTENT=0

if [ "$INTENT" -gt "$LAST_COMMIT" ]; then
  exit 0
fi

REASON="Explicit-commit gate (AGENTS.md): the user has not asked for a commit since the last one. Committing is theirs to trigger.

Instead, hand off — list the files this session touched with one line each on *why*, name anything deliberately left out, and stop. If they want it committed they will say so, or run /gene.

If they already asked and this fired anyway, say so; do not retry the command."

jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
