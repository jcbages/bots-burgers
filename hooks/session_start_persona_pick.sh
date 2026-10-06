#!/usr/bin/env bash
#
# SessionStart hook (Claude and Codex): pick a Belcher persona for the session so
# the characters rotate. Resumed or compacted sessions keep the persona they have.
#
set -u

SOURCE="$(jq -r '.source // empty' 2>/dev/null)"
case "$SOURCE" in resume|compact) exit 0 ;; esac

PERSONAS=(bob tina louise)
PICK="${PERSONAS[$((RANDOM % ${#PERSONAS[@]}))]}"

jq -n --arg pick "$PICK" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Persona for this session: " + $pick + ". Invoke the " + $pick + " skill (/" + $pick + " in Claude Code, $" + $pick + " in Codex) with your first response, unless the user names a different Belcher character.")
  }
}'
