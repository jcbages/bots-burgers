#!/usr/bin/env bash
#
# Tests for require_dod.sh — the Definition-of-Done Stop gate.
# Run: hooks/test/require_dod_test.sh
#
# The subtle cases, each one below: the gate must not match its own block message,
# must read a multi-line record whole, and must not trust role=="user" as provenance
# when agent reports wear that role too. A gate nobody tests is a suggestion.
set -u

# DOD_HOOK lets you point the suite at another revision of the hook, to confirm a
# case actually goes red against the version that had the bug.
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${DOD_HOOK:-$HOOKS_DIR/require_dod.sh}"
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
# The shape the harness actually replays a Stop refusal in — isMeta, and the reason
# wrapped in "Stop hook feedback:". Verified against every such record on this
# machine; a hand-written approximation only proves the guess is self-consistent.
own_block='{"isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\nDefinition of Done gate (AGENTS.md): this session edited product code but is missing:\n- Run the touched tests.\nComplete the missing steps, then finish. If the user explicitly wants to skip verification, they can reply '"'"'skip dod'"'"'."}}'
pasted_block='{"message":{"role":"user","content":"Definition of Done gate (AGENTS.md): this session edited product code but is missing:\n- Run the touched tests."}}'
agent_report='{"type":"user","userType":"external","message":{"role":"user","content":"<task-notification>\n<result>Verdict: SHIP IT. Note the gate is bypassed when the user replies skip dod.</result>\n</task-notification>"}}'
hook_feedback='{"isMeta":true,"message":{"role":"user","content":"You were blocked; you may reply skip dod to bypass."}}'
command_stdout='{"message":{"role":"user","content":"<local-command-stdout>reply `skip dod` to bypass it for a session</local-command-stdout>"}}'
malformed='{"message":{"role":"user","content":"truncated'

# Auto mode edits source through Bash, which Edit/Write-only gating never saw.
bash_heredoc='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > app/lib/models/streak.dart <<EOF\nclass Streak {}\nEOF"}}]}}'
bash_sed='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -i .bak s/foo/bar/ server/src/guards.ts"}}]}}'
bash_tee='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo x | tee lib/theme/tokens.dart"}}]}}'
bash_read='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat app/lib/models/streak.dart"}}]}}'
bash_grep='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep -rn Streak app/lib/models/streak.dart"}}]}}'
bash_doc='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > README.md <<EOF\nhi\nEOF"}}]}}'
bash_quoted_target='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > \"app/lib/models/streak.dart\" <<EOF\nclass Streak {}\nEOF"}}]}}'
bash_sed_chain='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"sed -i .bak s/a/b/ server/src/guards.ts && npm run build"}}]}}'
read_test_file='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat hooks/test/require_dod_test.sh"}}]}}'
write_test_file='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > hooks/test/new_test.sh <<EOF\nx\nEOF"}}]}}'
bash_quoted='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 - <<PY\nfixture = \"cat > app/lib/models/streak.dart\"\nPY"}}]}}'
ran_shell='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"hooks/test/require_dod_test.sh"}}]}}'
ran_bats='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bats test/"}}]}}'
bash_scratch='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > /tmp/scratch/probe.ts <<EOF\nx\nEOF"}}]}}'

passed=0
failed=0

expect_in() { # <cwd> <PASS|BLOCK> <name> <transcript line>...
  local cwd="$1" want="$2" name="$3" line got out
  shift 3
  : > "$WORK/t.jsonl"
  for line in "$@"; do printf '%s\n' "$line" >> "$WORK/t.jsonl"; done
  out="$(jq -n --arg tp "$WORK/t.jsonl" --arg cwd "$cwd" --arg sid "${SID:-}" \
    '{transcript_path:$tp, cwd:$cwd} + (if $sid == "" then {} else {session_id:$sid} end)' | "$HOOK")"
  [ -z "$out" ] && got=PASS || got=BLOCK
  if [ "$got" = "$want" ]; then
    passed=$((passed + 1)); printf '  ok   %s\n' "$name"
  else
    failed=$((failed + 1)); printf '  FAIL %s — want %s, got %s\n' "$name" "$want" "$got"
  fi
}

expect() { expect_in "$PROJECT" "$@"; } # <PASS|BLOCK> <name> <transcript line>...

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

echo "== Bash-written source counts as an edit (auto mode's real path) =="
expect BLOCK "heredoc into a .dart file"          "$bash_heredoc"
expect BLOCK "sed -i on a .ts file"               "$bash_sed"
expect BLOCK "tee into a .dart file"              "$bash_tee"
expect PASS  "reading a source file is not an edit" "$bash_read"
expect PASS  "grepping a source file is not an edit" "$bash_grep"
expect PASS  "heredoc into README.md still passes" "$bash_doc"
expect PASS  "scratchpad writes are not product code" "$bash_scratch"
expect PASS  "Bash edit + tests + review satisfies" "$bash_heredoc" "$ran_flutter" "$skill_fisch"
expect PASS  "a path merely quoted inside a heredoc" "$bash_quoted"
expect BLOCK "a QUOTED redirect target"           "$bash_quoted_target"
expect BLOCK "sed -i followed by && something"    "$bash_sed_chain"

echo "== a shell-script suite is a test runner too =="
expect PASS  "*_test.sh satisfies the test step"   "$bash_heredoc" "$ran_shell" "$skill_fisch"
expect PASS  "bats satisfies the test step"        "$bash_heredoc" "$ran_bats" "$skill_fisch"
expect BLOCK "READING a _test.sh is not running it" "$bash_heredoc" "$read_test_file" "$skill_fisch"
expect BLOCK "WRITING a _test.sh is not running it" "$bash_heredoc" "$write_test_file" "$skill_fisch"

echo "== a malformed line must not void a scan =="
expect PASS  "bypass survives a bad line before it" "$edit_src" "$malformed" "$user_skip"
expect BLOCK "gate still engages after a bad line"  "$malformed" "$edit_src"

# A gate that can refuse forever hangs an unattended session, so it must let go
# after MAX_BLOCKS. One earlier refusal is not enough — that case stays blocked
# above, where it proves the gate does not read its own message as consent.
echo "== liveness: the gate lets go rather than pinning a session =="
expect BLOCK "two prior blocks still refuse"       "$edit_src" "$own_block" "$own_block"
expect PASS  "three prior blocks release"          "$edit_src" "$own_block" "$own_block" "$own_block"
# The cap must not be reachable by talking about it: an assistant explaining why it
# is blocked names the gate every turn, and counting mentions would let it out.
chatter='{"message":{"role":"assistant","content":[{"type":"text","text":"The Definition of Done gate (AGENTS.md) is firing again."}]}}'
quoted_mid='{"message":{"role":"user","content":"I know the Definition of Done gate (AGENTS.md): this session edited product code is annoying."}}'
expect BLOCK "assistant chatter cannot reach it"   "$edit_src" "$chatter" "$chatter" "$chatter"
expect BLOCK "a mid-sentence quote cannot either"  "$edit_src" "$quoted_mid" "$quoted_mid" "$quoted_mid"
# isMeta is the provenance: a human pasting the refusal back wears role "user" too.
expect BLOCK "a human pasting it cannot either"    "$edit_src" "$pasted_block" "$pasted_block" "$pasted_block"

# The real regression: a throwaway script written into the repo (the only place it
# can resolve the project's deps), run, and deleted. Nothing survives, so there is
# nothing to test or review — but the transcript still records the write.
echo "== a write that left nothing behind must not arm the gate =="
# Not under $WORK: mktemp lands in /var/folders, which source_write_targets already
# discards as scratch, so a fixture there would exclude the Bash-write case before
# this section ever tested it.
GITPROJ="$HOME/.cache/dod-fixture-$$"
trap 'rm -rf "$WORK" "$GITPROJ"' EXIT
rm -rf "$GITPROJ"; mkdir -p "$GITPROJ/src"
git -C "$GITPROJ" init -q || exit 1
printf 'x\n' > "$GITPROJ/src/kept.ts"

edit_kept='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$GITPROJ'/src/kept.ts"}}]}}'
edit_gone='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$GITPROJ'/src/gone.ts"}}]}}'
bash_gone='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > '$GITPROJ'/src/gone.ts <<EOF\nx\nEOF"}}]}}'
bash_rm='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"rm -f '$GITPROJ'/src/gone.ts"}}]}}'

expect_in "$GITPROJ" BLOCK "an edit still on disk arms it"   "$edit_kept"
expect_in "$GITPROJ" PASS  "an edit since deleted does not"  "$edit_gone"
expect_in "$GITPROJ" PASS  "Bash write then rm does not"     "$bash_gone" "$bash_rm"
expect_in "$GITPROJ" BLOCK "a surviving edit still arms it"  "$edit_gone" "$edit_kept"
expect_in "$PROJECT" BLOCK "non-git project keeps old gating" "$edit_src"

# Concurrency (AGENTS.md): another agent dirtying the tree is not this session's
# work. The gate reads the transcript, so their edits must stay invisible to it.
echo "== another agent's edits must not arm this session's gate =="
printf 'y\n' > "$GITPROJ/src/other_agent.ts"
expect_in "$GITPROJ" PASS  "a file only they touched"        "$edit_gone"

# Names that CAN collide: matching a deleted path by basename, or by substring, lets
# a file someone else is working on vouch for one this session removed — and the gate
# then names a path that no longer exists, so no remedy can reach it.
mkdir -p "$GITPROJ/sub"
printf 'y\n' > "$GITPROJ/sub/gone.ts"
printf 'y\n' > "$GITPROJ/src/one.ts"
edit_gone_sub='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$GITPROJ'/src/gone.ts"}}]}}'
expect_in "$GITPROJ" PASS "same basename in another dir"     "$edit_gone_sub"
rm -f "$GITPROJ/sub/gone.ts"
expect_in "$GITPROJ" PASS "a substring of the deleted name"  "$edit_gone_sub"
rm -f "$GITPROJ/src/one.ts"

# An Edit path is project-relative already, so it is matched whole. Only a Bash write
# can be named from a subdirectory, and only it accepts a tail match — otherwise a
# deeper file sharing the tail would vouch for a deleted one.
mkdir -p "$GITPROJ/packages/a/src"
printf 'y\n' > "$GITPROJ/packages/a/src/gone.ts"
expect_in "$GITPROJ" PASS "a deeper path with the same tail" "$edit_gone_sub"
rm -rf "$GITPROJ/packages"

# The Bash side is the reason the tail match exists: a write named from a directory
# the session cd'd into resolves against no exact path. The second case is the
# collision that buys it — accepted deliberately, so it is asserted, not discovered.
mkdir -p "$GITPROJ/sub/src" "$GITPROJ/packages/a/src"
printf 'y\n' > "$GITPROJ/sub/src/live.ts"
printf 'y\n' > "$GITPROJ/packages/a/src/gone.ts"
bash_sub_live='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cd '$GITPROJ'/sub && cat > src/live.ts <<EOF\nx\nEOF"}}]}}'
bash_sub_gone='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cd '$GITPROJ'/sub && cat > src/gone.ts <<EOF\nx\nEOF"}}]}}'
expect_in "$GITPROJ" BLOCK "a cd'd write that survived"      "$bash_sub_live"
expect_in "$GITPROJ" BLOCK "the tail collision it accepts"   "$bash_sub_gone"
rm -rf "$GITPROJ/packages" "$GITPROJ/sub"

# Committed work is still this session's work. A branch with no upstream cannot
# answer "differs from the baseline", and treating that silence as "nothing changed"
# switches the gate off — the failure mode is a bypass, not a nag.
echo "== committed work must still arm the gate =="
COMMITTED="$HOME/.cache/dod-committed-$$"
trap 'rm -rf "$WORK" "$GITPROJ" "$COMMITTED"' EXIT
rm -rf "$COMMITTED"; mkdir -p "$COMMITTED/src"
git -C "$COMMITTED" init -q || exit 1
printf 'x\n' > "$COMMITTED/src/thing.ts"
git -C "$COMMITTED" add -A >/dev/null 2>&1
git -C "$COMMITTED" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
edit_committed='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$COMMITTED'/src/thing.ts"}}]}}'
expect_in "$COMMITTED" BLOCK "clean tree, no upstream"       "$edit_committed"
rm -rf "$COMMITTED"

# The domain map records where things live, so it goes stale when files appear or
# vanish — not when a line inside one changes. Its own fixture, because arming this
# condition would change what every case above expects.
echo "== keeping the domain map current =="
MAPPROJ="$HOME/.cache/dod-map-fixture-$$"
trap 'rm -rf "$WORK" "$GITPROJ" "$MAPPROJ"' EXIT
rm -rf "$MAPPROJ"; mkdir -p "$MAPPROJ/src"
git -C "$MAPPROJ" init -q 2>/dev/null
printf '# Map\n' > "$MAPPROJ/PROJECT_DOMAIN.md"
printf 'x\n' > "$MAPPROJ/src/kept.ts"
printf 'y\n' > "$MAPPROJ/src/added.ts"

m_edit='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$MAPPROJ'/src/kept.ts"}}]}}'
m_write='{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'$MAPPROJ'/src/added.ts"}}]}}'
m_write_doc='{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'$MAPPROJ'/NOTES.md"}}]}}'
m_write_scratch='{"message":{"content":[{"type":"tool_use","name":"Write","input":{"command":"x","file_path":"/tmp/scratch/probe.ts"}}]}}'
m_rm='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"rm -f '$MAPPROJ'/src/kept.ts"}}]}}'
m_map_edit='{"message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"'$MAPPROJ'/PROJECT_DOMAIN.md"}}]}}'
m_map_read='{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"'$MAPPROJ'/PROJECT_DOMAIN.md"}}]}}'

expect_in "$MAPPROJ" PASS  "editing a file leaves it current" "$m_edit" "$ran_npm" "$skill_fisch"

# Write overwrites as readily as it creates, so the tool call alone cannot tell an
# addition from a rewrite. Only a path git does not already track is new.
git -C "$MAPPROJ" add src/kept.ts >/dev/null 2>&1
git -C "$MAPPROJ" -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1
m_rewrite='{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'$MAPPROJ'/src/kept.ts"}}]}}'
expect_in "$MAPPROJ" PASS  "rewriting a tracked file"        "$m_rewrite" "$ran_npm" "$skill_fisch"
expect_in "$MAPPROJ" BLOCK "adding a source file stales it"   "$m_write" "$ran_npm" "$skill_fisch"
expect_in "$MAPPROJ" BLOCK "removing one stales it"           "$m_edit" "$m_rm" "$ran_npm" "$skill_fisch"
expect_in "$MAPPROJ" PASS  "updating the map settles it"      "$m_write" "$ran_npm" "$skill_fisch" "$m_map_edit"

# require_domain_map.sh already forces the map to be *read*, so crediting a read
# here would make the condition unreachable in every real session.
expect_in "$MAPPROJ" BLOCK "reading it is not updating it"    "$m_write" "$ran_npm" "$skill_fisch" "$m_map_read"

# A session told to prefer Bash writes the map through a heredoc, whose body is
# stripped before the transcript is read — so no parse of it can see the edit. The
# ledger is the only record of who wrote what, and it does not care which tool did.
LED="$HOOKS_DIR/session_ledger.sh"
ledger_hook() { printf '{"session_id":"S1","cwd":"%s","tool_use_id":"t1"}' "$MAPPROJ" | "$LED" "$1" >/dev/null 2>&1; }
( cd "$MAPPROJ" && ledger_hook pre && printf '# Map\nnow current\n' > PROJECT_DOMAIN.md && ledger_hook post )
SID=S1 expect_in "$MAPPROJ" PASS  "a map written by Bash settles it"  "$m_write" "$ran_npm" "$skill_fisch"
SID=  expect_in "$MAPPROJ" BLOCK  "and only for the session that wrote it" "$m_write" "$ran_npm" "$skill_fisch"

expect_in "$MAPPROJ" PASS  "a new doc is not structure"       "$m_edit" "$m_write_doc" "$ran_npm" "$skill_fisch"
expect_in "$MAPPROJ" PASS  "a scratch file is not structure"  "$m_edit" "$m_write_scratch" "$ran_npm" "$skill_fisch"

# A file created and deleted in one session leaves nothing for the map to describe.
m_write_gone='{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"'$MAPPROJ'/src/gone.ts"}}]}}'
m_rm_gone='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"rm -f '$MAPPROJ'/src/gone.ts"}}]}}'
expect_in "$MAPPROJ" PASS  "created then deleted is a no-op"  "$m_edit" "$m_write_gone" "$m_rm_gone" "$ran_npm" "$skill_fisch"

# A project with no map has nothing to keep current.
expect_in "$GITPROJ" PASS  "no map, nothing to update"        "$edit_kept" "$ran_npm" "$skill_fisch"
rm -rf "$MAPPROJ"

echo
printf '%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
