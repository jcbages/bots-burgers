#!/usr/bin/env bash
#
# PreToolUse hook (Bash): note a `git commit` that takes whatever happens to be
# staged. `.git/index` is one file shared by every agent working in this tree, so
# `git add` there is a read-modify-write race with a commit as the payload — one
# agent stages, another commits, and the second one's history carries the first
# one's half-finished work. Naming the paths, or building the commit in a private
# index (`GIT_INDEX_FILE` + `commit-tree`, see /gene step 3), avoids that. This
# advises and lets the commit through; a mixed commit is sorted out later, on a
# branch that always converges. Wired globally by install.sh.
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"
# shellcheck source=hooks/lib/advice.sh
. "$REPO_DIR/lib/advice.sh"

CMD="$(jq -r '.tool_input.command // empty' | strip_heredoc_bodies)"

# Only the porcelain sweeps an index it did not build. `commit-tree` commits a tree
# assembled elsewhere — that is the flow this gate steers toward, so it stays silent.
printf '%s' "$CMD" \
  | grep -qE '(^|[;&|[:space:]])([A-Za-z0-9_./-]*/)?git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)' \
  || exit 0

# A worktree has its own index, and scratch space is a fixture. Neither is shared.
GIT_DIR="$(printf '%s\n' "$CMD" | git_working_dir)"
if [ -n "$GIT_DIR" ] && printf '%s' "$GIT_DIR" | grep -qE "$SCRATCH_PATH"; then
  exit 0
fi

# A quoted body is the message, not the argument list: `-m "fix -- really"` names
# no paths, and `-m "commit -a"` stages nothing. Messages span lines, so join them
# first; otherwise a multi-line quote hides the `--` pathspec that follows it.
ARGS="$(printf '%s' "$CMD" | tr '\n' ' ' | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')"

# `-a` stages every tracked change in the tree, which is the whole hazard in one
# flag. `--amend` is a double dash, so a short cluster never matches it.
SWEEPS_ALL='commit([[:space:]]+--?[^[:space:]]+)*[[:space:]]+-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)'
# Otherwise the commit is scoped only if a `--` pathspec follows it.
SCOPED='commit([[:space:]]|$)[^;&|]*[[:space:]]--[[:space:]]'

if printf '%s' "$ARGS" | grep -qE "$SWEEPS_ALL" \
  || ! printf '%s' "$ARGS" | grep -qE "$SCOPED"; then
  advise_tool "Scoped-commit gate: this commit takes whatever is staged in the shared .git/index, which may include another agent's work. Name the paths instead (git commit -m '...' -- path/a path/b), or use the gene skill's scripts/commit-mine for a private-index commit."
fi
