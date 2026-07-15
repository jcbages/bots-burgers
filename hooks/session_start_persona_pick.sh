#!/usr/bin/env bash
#
# SessionStart hook: pick a work persona for this session and ask Claude to invoke
# it before doing anything else. Rotates across sessions so no single persona
# dominates. Wired globally by install.sh (see merge_settings).
#
set -u

PERSONAS=(bob tina louise)
PICK="${PERSONAS[$((RANDOM % ${#PERSONAS[@]}))]}"

jq -n --arg pick "$PICK" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Persona rotation for this session: invoke /" + $pick + " now before any other work, unless the user explicitly requests a different persona (/bob, /tina, or /louise) in their first prompt. This replaces waiting until the first Edit/Write to pick one.")
  }
}'
