#!/usr/bin/env bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/../session_start_persona_pick.sh"

passed=0; failed=0
check() {
  if [ "$1" = "$2" ]; then
    passed=$((passed+1)); printf '  ok   %s\n' "$3"
  else
    failed=$((failed+1)); printf '  FAIL %s — want %s, got %s\n' "$3" "$1" "$2"
  fi
}

picks=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  out="$(printf '{"source":"startup"}' | bash "$HOOK")"
  picks="$picks $(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | capture("Persona for this session: (?<p>[a-z]+)\\.").p')"
done
check "SessionStart" "$(printf '{"source":"startup"}' | bash "$HOOK" | jq -r '.hookSpecificOutput.hookEventName')" "startup emits SessionStart context"
check "" "$(printf '%s\n' $picks | grep -v -x -E 'bob|tina|louise')" "picks only bob, tina, or louise"
check "1" "$([ "$(printf '%s\n' $picks | sort -u | wc -l)" -gt 1 ] && echo 1 || echo 0)" "picks rotate across sessions"
check "1" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -c -F 'in Codex')" "context names the Codex invocation"
check "" "$(printf '{"source":"resume"}' | bash "$HOOK")" "resumed sessions keep their persona"
check "" "$(printf '{"source":"compact"}' | bash "$HOOK")" "compacted sessions keep their persona"
check "SessionStart" "$(printf '{"source":"clear"}' | bash "$HOOK" | jq -r '.hookSpecificOutput.hookEventName')" "cleared sessions get a new persona"
check "SessionStart" "$(printf 'not json' | bash "$HOOK" | jq -r '.hookSpecificOutput.hookEventName')" "malformed input still picks a persona"
check "SessionStart" "$(bash "$HOOK" </dev/null | jq -r '.hookSpecificOutput.hookEventName')" "empty input still picks a persona"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
