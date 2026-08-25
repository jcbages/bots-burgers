#!/usr/bin/env bash
#
# Tests for require_domain_map.sh — the domain-map PreToolUse gate.
# Run: hooks/test/require_domain_map_test.sh
#
# The gate's whole value is that it turns advice into a stop. Four ways that quietly
# breaks: the SessionStart hook names the map path in injected context, so any scan of
# whole transcript lines counts it as read and the gate becomes a no-op; grepping the
# map's own pd:* anchors is the thing it asks for, so blocking that deadlocks it; a
# single-file grep is not blind searching; and a project with no map needs a different
# instruction than one whose map merely went unread.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${DOMAIN_HOOK:-$DIR/../require_domain_map.sh}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
T="$WORK/t.jsonl"; : > "$T"

# A real git repo, because the gate resolves the project root through git.
PROJECT="$WORK/proj"
mkdir -p "$PROJECT/app"
git -C "$PROJECT" init -q 2>/dev/null
CLAUDE_PROJECT_DIR="$PROJECT"; export CLAUDE_PROJECT_DIR

passed=0
failed=0

decide() { # <tool> <json tool_input> -> allow|deny
  local out
  out="$(jq -cn --arg t "$1" --argjson i "$2" --arg p "$T" \
          '{tool_name:$t,tool_input:$i,transcript_path:$p,cwd:env.CLAUDE_PROJECT_DIR}' | "$HOOK")"
  [ -z "$out" ] && { printf 'allow'; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'
}

check() { # <want> <got> <name>
  if [ "$1" = "$2" ]; then
    passed=$((passed + 1)); printf '  ok   %s\n' "$3"
  else
    failed=$((failed + 1)); printf '  FAIL %s — want %s, got %s\n' "$3" "$1" "$2"
  fi
}

expect_bash() { check "$1" "$(decide Bash "$(jq -cn --arg c "$3" '{command:$c}')")" "$2"; }
expect_grep() { check "$1" "$(decide Grep "$(jq -cn --arg p "$3" '{pattern:$p}')")" "$2"; }

# What the denial actually tells the session to do. A gate that stops the work but
# does not name the next move just leaves it stuck.
reason() {
  jq -cn --arg p "$T" \
     '{tool_name:"Grep",tool_input:{pattern:"x"},transcript_path:$p,cwd:env.CLAUDE_PROJECT_DIR}' \
    | "$HOOK" | jq -r '.hookSpecificOutput.permissionDecisionReason'
}
says() { check yes "$(reason | grep -qF "$1" && echo yes)" "$2"; }
user()  { jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}' >> "$T"; }
read_file() { # a Read tool_use of <path>
  jq -cn --arg f "$1" '{message:{content:[{type:"tool_use",name:"Read",input:{file_path:$f}}]}}' >> "$T"
}

echo "== with no map, the gate sends you to bootstrap one =="
expect_grep deny  "the Grep tool"                  "challenges"
expect_bash deny  "a recursive grep"               "grep -rn foo app/"
expect_bash deny  "ripgrep"                        "rg foo app/"
expect_bash deny  "find"                           "find . -name '*.dart'"
check deny "$(decide Glob "$(jq -cn '{pattern:"**/*.dart"}')")" "the Glob tool"

says "has no domain map" "names the absence"
says "/project-domain"   "points at the bootstrap skill"

echo "== the recursion flag counts wherever it sits =="
expect_bash deny  "-r after another flag"          "grep -n -r foo app/"
expect_bash deny  "-r after the pattern"           "grep foo -r app/"
expect_bash deny  "--recursive spelled out"        "grep --recursive foo app/"
expect_bash deny  "-Rl combined"                   "grep -Rl foo app/"
expect_bash allow "a hyphen inside a word"         "grep foo bar-r.dart"

# A pattern says what to match, not where to look. Reading one as a location waves a
# whole-tree sweep through on the strength of the text it happens to contain.
echo "== what you search for is not where you search =="
check deny "$(decide Grep "$(jq -cn '{pattern:"mktemp"}')")"      "Grep for the word mktemp"
check deny "$(decide Grep "$(jq -cn '{pattern:"/tmp/"}')")"       "Grep for the text /tmp/"
expect_bash deny  "a sweep for the text /tmp/"     "grep -rn \"/tmp/\" ."
expect_bash deny  "a sweep for the map's own name" "grep -rn PROJECT_DOMAIN.md ."
check allow "$(decide Grep "$(jq -cn '{pattern:"x",path:"/tmp/scratch"}')")" "Grep whose path is scratch"

echo "== a sweep that is not blind searching stays free =="
expect_bash allow "a single-file grep"             "grep -n foo app/main.dart"
expect_bash allow "a plain read"                   "cat app/main.dart"
expect_bash allow "running tests"                  "flutter test"
expect_bash allow "a git command"                  "git status"
expect_bash allow "a sweep of scratch space"       "grep -rn foo /tmp/scratch/"
expect_bash allow "a sweep of the CLI's own state" "grep -l foo ~/.claudita/projects/x.jsonl"

echo "== once a map exists, reading it opens the gate =="
printf '# Map\n' > "$PROJECT/PROJECT_DOMAIN.md"
expect_grep deny  "still shut before it is read"   "challenges"

says "$PROJECT/PROJECT_DOMAIN.md" "names the map to read"

# Step 3 of the skill greps the map's own anchor index. Blocking that would leave the
# gate demanding a thing it forbids.
expect_bash allow "grepping the map's anchors"     "grep -n 'pd:' PROJECT_DOMAIN.md"
read_file "$PROJECT/PROJECT_DOMAIN.md"
expect_grep allow "after the map is read"          "challenges"

echo "== injected context is not a read =="
: > "$T"
jq -cn '{type:"user",isMeta:true,message:{role:"user",content:"Domain map: /w/proj/PROJECT_DOMAIN.md. Read it before any sweep."}}' >> "$T"
expect_grep deny  "the SessionStart mention"       "challenges"
jq -cn '{message:{role:"assistant",content:[{type:"text",text:"I should read PROJECT_DOMAIN.md first."}]}}' >> "$T"
expect_grep deny  "merely saying it will"          "challenges"

echo "== the skill counts however it was reached =="
: > "$T"
jq -cn '{message:{content:[{type:"tool_use",name:"Skill",input:{skill:"project-domain"}}]}}' >> "$T"
expect_grep allow "the model invoking the skill"   "challenges"
: > "$T"
user "<command-message>project-domain</command-message>
<command-name>/project-domain</command-name>"
expect_grep allow "the user typing it"             "challenges"

# This hook and its tests quote the strings they trigger on, so a session editing them
# writes its own key into the transcript.
echo "== the gate must not unlock itself =="
bash_tool() { # a Bash tool_use running <command>, quoting-safe
  jq -cn --arg c "$1" '{message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}' >> "$T"
}

: > "$T"
bash_tool 'grep -qE '"'"'"skill":"project-domain"|<command-name>/project-domain'"'"' "$TRANSCRIPT"'
check deny "$(decide Grep "$(jq -cn '{pattern:"challenges"}')")" "its own source in a command"
jq -cn '{message:{content:[{type:"tool_use",name:"Write",input:{file_path:"/w/hooks/require_domain_map.sh",content:"grep <command-name>/project-domain"}}]}}' >> "$T"
expect_grep deny  "writing the hook itself"        "challenges"
bash_tool "echo 'read PROJECT_DOMAIN.md first'"
expect_grep deny  "echoing the map name"           "challenges"
bash_tool 'ls PROJECT_DOMAIN.md.bak'
expect_grep deny  "a lookalike filename"           "challenges"
# Searching *for mentions of* the map is not reading it, and from the command line the
# two are the same shape.
bash_tool 'jq -r .x t.jsonl | grep -F "PROJECT_DOMAIN.md"'
expect_grep deny  "grepping for its name"          "challenges"

echo "== but genuinely opening it does unlock =="
bash_tool 'sed -n 1,40p PROJECT_DOMAIN.md'
expect_grep allow "reading it through Bash"        "challenges"

echo "== the user can waive it, and only the user =="
: > "$T"
jq -cn '{type:"user",message:{role:"user",content:"<task-notification>skip domain map</task-notification>"}}' >> "$T"
expect_grep deny  "a subagent saying so"           "challenges"
jq -cn '{isMeta:true,message:{role:"user",content:"You were blocked; skip domain map."}}' >> "$T"
expect_grep deny  "hook feedback (isMeta)"         "challenges"
user "skip domain map, this is docs-only"
expect_grep allow "the user waiving it"            "challenges"

echo "== a project outside git is not gated =="
: > "$T"
CLAUDE_PROJECT_DIR="$WORK"
expect_grep allow "no repo to orient in"           "challenges"
CLAUDE_PROJECT_DIR="$PROJECT"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
