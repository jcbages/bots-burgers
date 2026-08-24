#!/usr/bin/env bash
#
# Tests for block_branch_creation.sh — "always work on main".
# Run: hooks/test/block_branch_creation_test.sh
#
# The gate long matched only two spellings, so the force-create flags and plain
# `git branch <name>` created branches freely. Inspecting and deleting branches must
# stay free, or the gate just becomes something to work around.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${BRANCH_HOOK:-$DIR/../block_branch_creation.sh}"
T="$(mktemp)"; trap 'rm -f "$T"' EXIT
# shellcheck source=hooks/test/pretooluse_helper.sh
. "$DIR/pretooluse_helper.sh"

echo "== creating a branch is denied, every spelling =="
expect_cmd deny  "checkout -b"                "git checkout -b feature"
expect_cmd deny  "checkout -B (force create)" "git checkout -B feature"
expect_cmd deny  "switch -c"                  "git switch -c feature"
expect_cmd deny  "switch -C"                  "git switch -C feature"
expect_cmd deny  "plain git branch <name>"    "git branch feature"
expect_cmd deny  "chained after &&"           "git add . && git checkout -b feature"
expect_cmd deny  "a flag before -b"           "git checkout -q -b feature"
expect_cmd deny  "switch --create"            "git switch --create feature"
expect_cmd deny  "checkout --force-create"    "git checkout --force-create feature"
expect_cmd deny  "git branch -f <name>"       "git branch -f feature origin/main"
expect_cmd deny  "git worktree add -b"        "git worktree add -b feature ../wt"

echo "== inspecting and deleting branches stays free =="
expect_cmd allow "bare git branch"            "git branch"
expect_cmd allow "git branch -a"              "git branch -a"
expect_cmd allow "git branch --list"          "git branch --list"
expect_cmd allow "deleting a branch"          "git branch -d old-thing"
expect_cmd allow "renaming a branch"          "git branch -m old new"
expect_cmd allow "showing the current branch" "git branch --show-current"
expect_cmd allow "switching to an existing"   "git checkout main"
expect_cmd allow "switch without -c"          "git switch main"
expect_cmd allow "an unrelated command"       "grep -rn branch src/"
expect_cmd allow "a heredoc body quoting it"  "cat > notes.md <<XEOF
git checkout -b feature
XEOF"
report
