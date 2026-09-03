#!/usr/bin/env bash
#
# Shared harness for PreToolUse gates: feed a tool input, get a decision back.
# Source it after setting HOOK and T (transcript path), then call expect_*/report.
set -u

passed=0
failed=0

SESSION="${SESSION:-testsession}"

decide() { # <json tool_input> -> allow|warn|deny
  local out
  # A call the gate has nothing to say about produces no output at all.
  out="$(printf '{"tool_input":%s,"transcript_path":%s,"session_id":"%s"}' \
        "$1" "$(jq -Rn --arg t "$T" '$t')" "$SESSION" | "$HOOK")"
  [ -z "$out" ] && { printf 'allow'; return; }
  # Advice carries no decision, so absence of one is the signal — but only when the
  # advice is actually there. An output with neither is malformed, not permissive.
  printf '%s' "$out" | jq -r '.hookSpecificOutput
    | .permissionDecision // (if .additionalContext then "warn" else "malformed" end)'
}

check() { # <want> <got> <name>
  if [ "$1" = "$2" ]; then
    passed=$((passed + 1)); printf '  ok   %s\n' "$3"
  else
    failed=$((failed + 1)); printf '  FAIL %s — want %s, got %s\n' "$3" "$1" "$2"
  fi
}

expect_cmd()  { check "$1" "$(decide "$(jq -cn --arg c "$3" '{command:$c}')")" "$2"; }
expect_file() { check "$1" "$(decide "$(jq -cn --arg f "$3" '{file_path:$f}')")" "$2"; }

report() {
  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
}
