#!/usr/bin/env bash
#
# Tests for require_dod.sh — the Definition-of-Done Stop gate.
# Run: hooks/test/require_dod_test.sh
#
# This gate is load-bearing and has failed in subtle ways more than once: it matched
# its own block message, it excluded a marker line-wise from a multi-line record, and
# it trusted role=="user" as provenance when agent reports wear that role too. Every
# one of those is a case below. A gate nobody tests is a suggestion.
set -u

# DOD_HOOK lets you point the suite at another revision of the hook, to confirm a
# case actually goes red against the version that had the bug.
HOOK="${DOD_HOOK:-$(cd "$(dirname "$0")/.." && pwd)/require_dod.sh}"
PROJECT="/tmp/dod-fixture-project"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

edit_src='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$PROJECT'/server/src/guards.ts"}}]}}'
edit_doc='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$PROJECT'/README.md"}}]}}'
ran_npm='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}'
ran_flutter='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"flutter test"}}]}}'
skill_fisch='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"mr-fischoeder"}}]}}'
skill_review='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"code-review"}}]}}'
typed_fisch='{"message":{"content":[{"type":"text","text":"<command-name>/mr-fischoeder</command-name>"}]}}'
agent_fisch='{"message":{"content":[{"type":"tool_use","name":"Agent","input":{"prompt":"You are Mr. Fischoeder. Review this diff."}}]}}'
user_skip='{"message":{"role":"user","content":[{"type":"text","text":"skip dod"}]}}'
user_skip_str='{"message":{"role":"user","content":"Skip DOD please"}}'
assistant_skip='{"message":{"role":"assistant","content":[{"type":"text","text":"You may reply skip dod to bypass."}]}}'
tool_result_skip='{"message":{"role":"user","content":[{"type":"tool_result","content":"skip dod"}]}}'
own_block='{"message":{"role":"user","content":"Definition of Done gate (AGENTS.md): this session edited product code but is missing:\n- Run the touched tests.\nComplete the missing steps, then finish. If the user explicitly wants to skip verification, they can reply '"'"'skip dod'"'"'."}}'
agent_report='{"type":"user","userType":"external","message":{"role":"user","content":"<task-notification>\n<result>Verdict: SHIP IT. Note the gate is bypassed when the user replies skip dod.</result>\n</task-notification>"}}'
hook_feedback='{"isMeta":true,"message":{"role":"user","content":"You were blocked; you may reply skip dod to bypass."}}'
command_stdout='{"message":{"role":"user","content":"<local-command-stdout>reply `skip dod` to bypass it for a session</local-command-stdout>"}}'
malformed='{"message":{"role":"user","content":"truncated'

passed=0
failed=0

expect() { # <PASS|BLOCK> <name> <transcript line>...
  local want="$1" name="$2" line got out
  shift 2
  : > "$WORK/t.jsonl"
  for line in "$@"; do printf '%s\n' "$line" >> "$WORK/t.jsonl"; done
  out="$(jq -n --arg tp "$WORK/t.jsonl" --arg cwd "$PROJECT" \
    '{transcript_path:$tp, cwd:$cwd}' | "$HOOK")"
  [ -z "$out" ] && got=PASS || got=BLOCK
  if [ "$got" = "$want" ]; then
    passed=$((passed + 1)); printf '  ok   %s\n' "$name"
  else
    failed=$((failed + 1)); printf '  FAIL %s — want %s, got %s\n' "$name" "$want" "$got"
  fi
}

echo "== gating: which sessions are checked at all =="
expect BLOCK "source edit, nothing else"          "$edit_src"
expect PASS  "docs-only edit passes through"      "$edit_doc"
expect BLOCK "tests without a review"             "$edit_src" "$ran_npm"

echo "== the review requirement =="
expect PASS  "Skill(mr-fischoeder) satisfies"     "$edit_src" "$ran_npm" "$skill_fisch"
expect PASS  "user-typed /mr-fischoeder satisfies" "$edit_src" "$ran_npm" "$typed_fisch"
expect PASS  "Fischoeder subagent satisfies"      "$edit_src" "$ran_flutter" "$agent_fisch"
expect BLOCK "code-review no longer satisfies"    "$edit_src" "$ran_npm" "$skill_review"

echo "== the test requirement =="
expect BLOCK "review without tests"               "$edit_src" "$skill_fisch"
expect PASS  "flutter test counts as a runner"    "$edit_src" "$ran_flutter" "$skill_fisch"

echo "== the bypass: only a genuine human turn disarms the gate =="
expect PASS  "user types 'skip dod'"              "$edit_src" "$user_skip"
expect PASS  "user turn as a plain string"        "$edit_src" "$user_skip_str"
expect BLOCK "the gate's OWN block message"       "$edit_src" "$own_block"
expect BLOCK "a subagent report quoting it"       "$edit_src" "$agent_report"
expect BLOCK "hook feedback (isMeta) quoting it"  "$edit_src" "$hook_feedback"
expect BLOCK "command stdout quoting it"          "$edit_src" "$command_stdout"
expect BLOCK "an assistant turn quoting it"       "$edit_src" "$assistant_skip"
expect BLOCK "a tool_result quoting it"           "$edit_src" "$tool_result_skip"

echo "== a malformed line must not void a scan =="
expect PASS  "bypass survives a bad line before it" "$edit_src" "$malformed" "$user_skip"
expect BLOCK "gate still engages after a bad line"  "$malformed" "$edit_src"

echo
printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
