#!/usr/bin/env bash
#
# Tests for session_ledger.sh + bin/commit-mine — per-session attribution in a
# shared working tree. Run: hooks/test/session_ledger_test.sh
#
# The property under test is the one a shared tree destroys: after two sessions
# have written to one file, each must still be able to commit exactly its own
# lines. The interesting cases are the ones tools that work at git-hunk
# granularity get wrong — edits close enough together to coalesce into a single
# hunk — and the ones that must fail loudly rather than guess: the same line
# touched twice, and HEAD moving mid-commit.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
HOOK="$ROOT/hooks/session_ledger.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

passed=0; failed=0
check() { if [ "$1" = "$2" ]; then passed=$((passed+1)); printf '  ok   %s\n' "$3"
          else failed=$((failed+1)); printf '  FAIL %s\n       want: %s\n       got:  %s\n' "$3" "$1" "$2"; fi; }

cd "$W"
git init -q -b main .
git config user.email t@t; git config user.name t
seq 1 40 | sed 's/^/line/' > shared.rb
git add . && git commit -qm base

hook() { printf '{"session_id":"%s","cwd":"%s"}' "$2" "$W" | "$HOOK" "$1" >/dev/null 2>&1; }
edit() { perl -i -pe "s/^\Qline$2\E\$/line$2 $3/" "$1"; }
mine() { LEDGER_SESSION="$1" "$ROOT/bin/mine" "${2:---files}" 2>/dev/null; }
commit_mine() { local s="$1"; shift; LEDGER_SESSION="$s" "$ROOT/bin/commit-mine" "$@" 2>&1; }

echo "== two sessions edit the same file, 3 lines apart (one git hunk) =="
hook pre A;  edit shared.rb 10 A-EDIT;  hook post A
hook pre B;  edit shared.rb 13 B-EDIT;  hook post B
check "shared.rb" "$(mine A)" "A owns shared.rb"
check "shared.rb" "$(mine B)" "B owns shared.rb"
check "1" "$(mine A --stat >/dev/null; LEDGER_SESSION=A "$ROOT/bin/mine" | grep -c '^+line10 A-EDIT')" "A's diff has A's line"
check "0" "$(LEDGER_SESSION=A "$ROOT/bin/mine" | grep -c '^+line13 B-EDIT')" "A's diff does NOT have B's line"
check "1" "$(LEDGER_SESSION=B "$ROOT/bin/mine" | grep -c '^+line13 B-EDIT')" "B's diff has B's line"
check "0" "$(LEDGER_SESSION=B "$ROOT/bin/mine" | grep -c '^+line10 A-EDIT')" "B's diff does NOT have A's line"

echo "== each commits only its own lines =="
commit_mine A -m "A: line10" >/dev/null
check "1" "$(git show HEAD --format= -U0 | grep -c '^+line10 A-EDIT')" "A's commit has A's line"
check "0" "$(git show HEAD --format= -U0 | grep -c '^+line13 B-EDIT')" "A's commit lacks B's line"
commit_mine B -m "B: line13" >/dev/null
check "1" "$(git show HEAD --format= -U0 | grep -c '^+line13 B-EDIT')" "B's commit has B's line"
check "0" "$(git show HEAD --format= -U0 | grep -c 'line10')" "B's commit does not re-touch line10"
check "0" "$(git status --porcelain | wc -l | tr -d ' ')" "worktree is clean once both landed"
check "1" "$(grep -c '^line10 A-EDIT$' shared.rb)" "worktree kept A's edit"
check "1" "$(grep -c '^line13 B-EDIT$' shared.rb)" "worktree kept B's edit"

echo "== a new file, and a deleted file =="
hook pre A; printf 'brand new\n' > added.rb; hook post A
hook pre B; rm -f shared.rb;               hook post B
check "added.rb" "$(mine A)" "A owns the file it created"
commit_mine A -m "A: add file" >/dev/null
check "brand new" "$(git show HEAD:added.rb)" "the new file landed"
commit_mine B -m "B: delete" >/dev/null
check "1" "$(git show HEAD --format= --name-status | grep -c '^D.shared.rb')" "the deletion landed"

echo "== the same line touched by both is refused, not guessed =="
git checkout -q -- . 2>/dev/null; seq 1 40 | sed 's/^/line/' > two.rb
git add two.rb && git commit -qm "two.rb"
hook pre A; edit two.rb 5 FIRST;  hook post A
hook pre B; perl -i -pe 's/^line5 FIRST$/line5 SECOND/' two.rb; hook post B
before="$(git rev-parse HEAD)"
out="$(commit_mine B -m "B")"
check "1" "$(printf '%s' "$out" | grep -c 'two.rb')" "B is told two.rb could not be separated"
check "$before" "$(git rev-parse HEAD)" "B created no commit at all"
check "1" "$(git show HEAD:two.rb | grep -c '^line5$')" "the committed line5 is still untouched"

echo "== HEAD moving under a pending change is absorbed, not lost =="
hook pre A; edit two.rb 20 A2; hook post A
printf 'unrelated\n' > other.rb
git add other.rb && git commit -qm "another session landed"   # HEAD moves under A
commit_mine A -m "A: line20" >/dev/null
check "1" "$(git show HEAD --format= -U0 | grep -c '^+line20 A2')" "A's change still landed on the new HEAD"
check "1" "$(git show HEAD:other.rb | grep -c unrelated)" "the other session's file survived"
check "1" "$(git show HEAD --format= --name-only | grep -c '^two.rb$')" "A's commit touched only two.rb"

echo "== a path with a space in it =="
printf 'x\n' > "with space.rb"; git add "with space.rb" && git commit -qm "spaced"
hook pre A; printf 'x\nA line\n' > "with space.rb"; hook post A
check "with space.rb" "$(mine A)" "the spaced path is tracked whole"
commit_mine A -m "A: spaced" >/dev/null
check "1" "$(git show HEAD --format= --name-only | grep -c '^with space.rb$')" "the spaced path committed"

echo "== a session that undoes its own edit commits nothing =="
before="$(git rev-parse HEAD)"
hook pre A; edit two.rb 30 TEMP;                          hook post A
hook pre A; perl -i -pe 's/^line30 TEMP$/line30/' two.rb; hook post A
out="$(commit_mine A -m "A: noop")"
check "$before" "$(git rev-parse HEAD)" "no commit was created"
check "1" "$(printf '%s' "$out" | grep -c 'nothing to commit')" "and it says so"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
