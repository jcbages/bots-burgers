#!/usr/bin/env bash
#
# Tests for require_scoped_commit.sh — the shared-index PreToolUse gate.
# Run: hooks/test/require_scoped_commit_test.sh
#
# The gate exists because `.git/index` is one file every agent in a working tree
# shares, so a commit that takes "whatever is staged" takes whatever *they* staged.
# Three ways that quietly breaks: the plumbing form gets caught (it is the escape
# hatch the denial recommends), a worktree gets caught (its index is its own), or a
# commit *message* containing " -- " reads as a pathspec and waves the sweep through.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCOPED_HOOK:-$DIR/../require_scoped_commit.sh}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
T="$WORK/t.jsonl"; : > "$T"   # unread: this gate judges the command alone
# shellcheck source=hooks/test/pretooluse_helper.sh
. "$DIR/pretooluse_helper.sh"

echo "== a commit must name what it commits =="
expect_cmd deny  "a bare commit"               "git commit -m x"
expect_cmd deny  "staged, then committed"      "git add a.rb b.rb && git commit -m y"
expect_cmd allow "a pathspec-scoped commit"    "git commit -m x -- a.rb b.rb"
expect_cmd allow "a message with real spaces"  'git commit -m "Add the thing" -- app/a.rb'

echo "== -a sweeps the tree, pathspec or not =="
expect_cmd deny  "the -a flag"                 "git commit -a -m x"
expect_cmd deny  "the -am cluster"             'git commit -am "quick"'
expect_cmd deny  "--all spelled out"           "git commit --all -m x"
expect_cmd deny  "-a with a pathspec anyway"   "git commit -a -m x -- a.rb"

echo "== an amend commits the index too =="
expect_cmd deny  "a bare amend"                "git commit --amend --no-edit"
expect_cmd allow "a scoped amend"              "git commit --amend --no-edit -- a.rb"

echo "== the plumbing form is the recommended escape hatch =="
expect_cmd allow "commit-tree"                 'git commit-tree $tree -p $base -F /tmp/msg.txt'
expect_cmd allow "the ref move"                "git update-ref HEAD abc123 def456"
expect_cmd allow "a private-index add"         'GIT_INDEX_FILE=.git/gene-index git add -- a.rb'
expect_cmd allow "commit-mine, the sanctioned path" "bin/commit-mine -m x"
expect_cmd allow "unrelated git"               "git status"
# Command-shaped text is treated as a command, as in the sibling gate: a heredoc
# body is the way to quote one, and nothing else needs to.
expect_cmd allow "the bare word in an echo"    "echo commit"
expect_cmd deny  "an echo spelling it out"     "echo git commit -m x"

echo "== an index that is not shared is not the hazard =="
expect_cmd allow "a commit in mktemp"          'cd $(mktemp -d) && git commit -m init'
expect_cmd allow "a /mr-frond worktree"        "cd /tmp/mati/add-avatars && git commit -m x"
expect_cmd allow "an explicit git -C fixture"  "git -C /tmp/fixture commit -m probe"

echo "== a message is not an argument list =="
expect_cmd deny  "a message containing --"     'git commit -m "drop the -- separator"'
expect_cmd deny  "a message naming a path"     'git commit -m "fix a.rb -- properly"'
expect_cmd deny  "a message mentioning /tmp/"  'git commit -m "handle /tmp/ paths"'
expect_cmd allow "a heredoc body quoting one"  "cat > notes.md <<XEOF
git commit -m sneaky
XEOF"

report
