#!/usr/bin/env bash
#
# Tests for block_discard_changes.sh — "never discard changes you did not make".
# Run: hooks/test/block_discard_changes_test.sh
#
# The hazard is other agents' uncommitted work, so inspection and the additive half
# of these commands (stash pop, clean --dry-run) must stay free — a gate that denies
# reading is a gate people route around.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${DISCARD_HOOK:-$DIR/../block_discard_changes.sh}"
T="$(mktemp)"; trap 'rm -f "$T"' EXIT
# shellcheck source=hooks/test/pretooluse_helper.sh
. "$DIR/pretooluse_helper.sh"

echo "== discarding the working tree is denied =="
expect_cmd deny  "checkout -- <path>"      "git checkout -- src/a.rb"
expect_cmd deny  "checkout ."              "git checkout ."
expect_cmd deny  "checkout ./src"          "git checkout ./src"
expect_cmd deny  "checkout <ref> <path>"   "git checkout HEAD src/a.rb"
expect_cmd deny  "checkout -f <branch>"    "git checkout -f main"
expect_cmd deny  "switch --discard-changes" "git switch --discard-changes main"
expect_cmd deny  "restore <path>"          "git restore src/a.rb"
expect_cmd deny  "restore --worktree"      "git restore --staged --worktree src/a.rb"
expect_cmd deny  "reset --hard"            "git reset --hard HEAD"
expect_cmd deny  "reset --hard, chained"   "git fetch && git reset --hard origin/main"
expect_cmd deny  "bare git stash"          "git stash"
expect_cmd deny  "stash push"              "git stash push -m wip"
expect_cmd deny  "stash -u"                "git stash -u"
expect_cmd deny  "clean -fd"               "git clean -fd"
expect_cmd deny  "clean --force"           "git clean --force"
expect_cmd deny  "quoted pathspec"         "git checkout -- \"src/a.rb\""
expect_cmd deny  "inside a subshell"        "(git reset --hard)"
expect_cmd deny  "subshell with a cd"       "(cd hooks && git checkout -- .)"
expect_cmd deny  "sudo in front"            "sudo git clean -fd"
expect_cmd deny  "inside an if"             "if true; then git reset --hard; fi"
expect_cmd deny  "inside a for loop"        "for d in a b; do git clean -fd; done"
expect_cmd deny  "inside a while loop"      "while read f; do git checkout -- \$f; done < list"
expect_cmd deny  "inside a brace group"     "{ git reset --hard; }"
expect_cmd deny  "behind bash -c"           "bash -c \"git reset --hard\""
expect_cmd deny  "behind nohup"             "nohup git reset --hard"
expect_cmd deny  "behind an env assignment" "GIT_DIR=.git git reset --hard"
expect_cmd deny  "behind eval"              "eval \"git reset --hard\""
expect_cmd deny  "behind find -exec"        "find . -name '*.rb' -exec git checkout -- {} ;"
expect_cmd deny  "behind xargs -I {}"       "git diff --name-only | xargs -I {} git checkout -- {}"
expect_cmd deny  "behind sudo -u <user>"    "sudo -u someone git clean -fd"
expect_cmd deny  "a -c global before it"    "git -c core.fileMode=false reset --hard"
expect_cmd deny  "a --git-dir before it"    "git --git-dir .git reset --hard"
expect_cmd deny  "a --work-tree before it"  "git --work-tree . reset --hard"
expect_cmd deny  "a value-less global"      "git --no-pager reset --hard"
expect_cmd deny  "a \$( ) ref before --"     "git checkout \$(git merge-base main HEAD) -- ."
expect_cmd deny  "a \$( ) ref, no --"        "git checkout \$(cat ref.txt) src/"
expect_cmd deny  "a backticked ref"         "git checkout \`cat ref.txt\` -- ."
expect_cmd deny  "a substitution in an echo" "echo \`git reset --hard\`"
expect_cmd deny  "a dir named git first"    "find /Users/x/git -name '*.rb' -exec git checkout -- {} ;"
expect_cmd deny  "egrep is not a shield"    "egrep x f && git reset --hard"

echo "== reading, and the additive half, stays free =="
expect_cmd allow "checkout a branch"       "git checkout main"
expect_cmd allow "checkout -b"             "git checkout -b feature"
expect_cmd allow "switch a branch"         "git switch main"
expect_cmd allow "restore --staged only"   "git restore --staged src/a.rb"
expect_cmd allow "reset --soft"            "git reset --soft HEAD~1"
expect_cmd allow "bare reset (unstage)"    "git reset"
expect_cmd allow "stash list"              "git stash list"
expect_cmd allow "stash pop"               "git stash pop"
expect_cmd allow "clean --dry-run"         "git clean --dry-run"
expect_cmd allow "clean -nd"               "git clean -nd"
expect_cmd allow "git status"              "git status --short"
expect_cmd allow "an unrelated command"    "grep -rn checkout src/"
expect_cmd allow "grepping for the command" "grep -rn \"git reset --hard\" hooks/"
expect_cmd allow "echoing the command"     "echo \"run git checkout -- . first\" >> notes.md"
expect_cmd allow "grep behind sudo"        "sudo grep \"git reset --hard\" hooks/"
expect_cmd allow "sed rewriting the text"  "sed -i '' 's/x/git reset --hard/' notes.md"
expect_cmd allow "egrep quoting it"        "egrep \"git reset --hard\" hooks/"
expect_cmd allow "a substitution that reads" "echo \`git rev-parse HEAD\`"
expect_cmd allow "a message naming the rule" "git commit -m \"add a gate for git reset --hard\" -- notes.md"
expect_cmd allow "a message naming a pathspec" "git commit -m \"gate git checkout -- . too\""
expect_cmd allow "an unrelated substitution" "grep -rn \"git reset --hard\" \`pwd\`"
expect_cmd allow "restore -S (short flag)" "git restore -S src/a.rb"
expect_cmd allow "checkout <branch>, no such path" "git checkout some-feature-branch"
expect_cmd allow "a heredoc body quoting it" "cat > notes.md <<XEOF
git reset --hard
XEOF"

echo "== a worktree and scratch space hold nobody else's work =="
expect_cmd allow "git -C a scratch tree"   "git -C /tmp/ai-config/feature reset --hard"
expect_cmd allow "cd into scratch first"   "cd /tmp/ai-config/feature && git checkout -- ."

# The scratch cases above pass on the path alone, so the exemption that actually
# matters — a linked worktree anywhere — needs a real one. Built outside the temp
# dirs, or SCRATCH_PATH would answer for it, and outside the repo, whose tree other
# agents are working in.
WT="$HOME/.discard-gate-fixture-$$"; rm -rf "$WT"
mkdir -p "$WT/repo"
git -C "$WT/repo" init -q .
git -C "$WT/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WT/repo" worktree add -q "$WT/linked" -b probe
# Named `git` on purpose: the token that locates the command also matches a path.
git -C "$WT/repo" worktree add -q "$WT/git" -b probe-git
trap 'rm -f "$T"; rm -rf "$WT"' EXIT
check allow "$(decide "$(jq -cn --arg c "git -C $WT/linked reset --hard" '{command:$c}')")" \
  "a linked worktree outside scratch"
check deny  "$(decide "$(jq -cn --arg c "git -C $WT/repo reset --hard" '{command:$c}')")" \
  "and its shared parent is not"

echo "== the tree is shared wherever the call was made from =="
# git answers --git-common-dir relative to its own cwd, so a subdirectory of a plain
# repo looks exactly like a linked worktree unless both paths are asked for absolute.
mkdir -p "$WT/repo/sub"
CWD="$WT/repo/sub" expect_cmd deny  "cwd is a subdirectory"    "git reset --hard"
CWD="$WT/repo"     expect_cmd deny  "cwd is the repo root"     "git checkout -- ."
CWD="$WT/repo"     expect_cmd deny  "cd into a subdirectory"   "cd sub && git reset --hard"
CWD="$WT/repo"     expect_cmd allow "-C a worktree, alone"     "git -C $WT/linked status && git log"
CWD="$WT/repo"     expect_cmd deny  "-C a worktree, then reset here" "git -C $WT/linked status && git reset --hard"
CWD="$WT/linked"   expect_cmd allow "cwd is the worktree"      "git reset --hard"

echo "== a checkout naming one path is git's DWIM: the filesystem decides =="
# Rooted at the fixture, not at wherever the suite was launched from — this case
# asserts on what is on disk, so the disk it looks at has to be the fixture's.
: > "$WT/repo/tracked.txt"
CWD="$WT/repo" expect_cmd deny  "a relative path that exists" "git checkout tracked.txt"
CWD="$WT/repo" expect_cmd deny  "an absolute path"            "git checkout $WT/repo/tracked.txt"
CWD="$WT/repo" expect_cmd deny  "a ~-rooted path"             "git checkout ~/${WT##*/}/repo/tracked.txt"
CWD="$WT/repo" expect_cmd deny  "a path under a cd"           "cd .. && git checkout repo/tracked.txt"
CWD="$WT/repo" expect_cmd allow "a name that is no path"      "git checkout tracked-branch"

echo "== a cd does not outlive the subshell that made it =="
CWD="$WT/repo" expect_cmd deny  "cd in a subshell, reset after" \
  "(cd $WT/linked && git status) && git reset --hard"
CWD="$WT/repo" expect_cmd allow "cd in a subshell, reset inside" \
  "(cd $WT/linked && git reset --hard)"
CWD="$WT/linked" expect_cmd deny  "a stray ) does not clear the cd" \
  "cd $WT/repo && echo ':)' && git reset --hard"
report
