#!/usr/bin/env bash
#
# Tests for require_persona.sh — no source edits before a persona is invoked.
# Run: hooks/test/require_persona_test.sh
#
# Auto mode writes files through Bash as often as through the edit tools, so one
# policy has to hold on both paths: fire on source writes, stay out of the way for
# reads, docs and everything else.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${PERSONA_HOOK:-$DIR/../require_persona.sh}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
T="$WORK/t.jsonl"; : > "$T"
# shellcheck source=hooks/test/pretooluse_helper.sh
. "$DIR/pretooluse_helper.sh"

DART_WRITE='cat > app/lib/streak.dart <<XEOF
class Streak {}
XEOF'

echo "== with no persona invoked =="
expect_file deny  "an Edit tool call"          "/proj/app/lib/streak.dart"
expect_file allow "a markdown Edit needs none" "/proj/README.md"
expect_file allow "a scratchpad Edit"          "/tmp/scratchpad/probe.ts"
expect_cmd  deny  "heredoc into a .dart file"  "$DART_WRITE"
expect_cmd  deny  "sed -i on a .ts file"       "sed -i .bak s/a/b/ server/src/guards.ts"
expect_cmd  deny  "a QUOTED redirect target"   "cat > \"app/lib/streak.dart\" <<XEOF
class Streak {}
XEOF"
expect_cmd  deny  "sed -i followed by &&"      "sed -i .bak s/a/b/ src/guards.ts && echo done"
expect_cmd  deny  "cp onto a source file"      "cp /tmp/new.dart app/lib/streak.dart"
expect_cmd  allow "reading a source file"      "cat app/lib/streak.dart"
expect_cmd  allow "grepping a source file"     "grep -rn Streak app/lib/streak.dart"
expect_cmd  allow "running tests"              "flutter test test/widget_test.dart"
expect_cmd  allow "writing a markdown file"    "cat > NOTES.md <<XEOF
hi
XEOF"
expect_cmd  allow "writing to the scratchpad"  "cat > /tmp/scratchpad/probe.ts <<XEOF
x
XEOF"

echo "== once a persona is invoked =="
printf '%s\n' '{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"tina"}}]}}' >> "$T"
expect_file allow "an Edit tool call"          "/proj/app/lib/streak.dart"
expect_cmd  allow "heredoc into a .dart file"  "$DART_WRITE"
report
