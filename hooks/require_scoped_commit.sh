#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny a `git commit` that takes whatever happens to be
# staged. `.git/index` is one file shared by every agent working in this tree, so
# `git add` there is a read-modify-write race with a commit as the payload — one
# agent stages, another commits, and the second one's history carries the first
# one's half-finished work. A commit must therefore name what it is committing, or
# be built in a private index (`GIT_INDEX_FILE` + `commit-tree`, see /gene step 3),
# which never touches the shared one at all. Wired globally by install.sh.
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

CMD="$(jq -r '.tool_input.command // empty' | strip_heredoc_bodies)"

# Only the porcelain sweeps an index it did not build. `commit-tree` commits a tree
# assembled elsewhere — that is the flow this gate steers toward, so it stays free.
printf '%s' "$CMD" \
  | grep -qE '(^|[;&|[:space:]])([A-Za-z0-9_./-]*/)?git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)' \
  || exit 0

# A worktree has its own index, and scratch space is a fixture. Neither is shared.
GIT_DIR="$(printf '%s\n' "$CMD" | git_working_dir)"
if [ -n "$GIT_DIR" ] && printf '%s' "$GIT_DIR" | grep -qE "$SCRATCH_PATH"; then
  exit 0
fi

# A quoted body is the message, not the argument list: `-m "fix -- really"` names
# no paths, and `-m "commit -a"` stages nothing.
ARGS="$(printf '%s' "$CMD" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')"

# `-a` stages every tracked change in the tree, which is the whole hazard in one
# flag. `--amend` is a double dash, so a short cluster never matches it.
SWEEPS_ALL='commit([[:space:]]+--?[^[:space:]]+)*[[:space:]]+-[a-zA-Z]*a[a-zA-Z]*([[:space:]]|$)'
# Otherwise the commit is scoped only if a `--` pathspec follows it.
SCOPED='commit([[:space:]]|$)[^;&|]*[[:space:]]--[[:space:]]'

if printf '%s' "$ARGS" | grep -qE "$SWEEPS_ALL" \
  || ! printf '%s' "$ARGS" | grep -qE "$SCOPED"; then
  REASON="Scoped-commit gate (AGENTS.md): .git/index is shared with every agent working in this tree, so a commit that takes whatever is staged can carry someone else's half-finished work into your history — and yours into theirs. Name what you are committing.

  git commit -m '...' -- path/a path/b

That commits the working-tree content of those paths and ignores every other staged path. For new files, or to commit only *some* hunks of a file another agent is also editing, build the commit in a private index instead (/gene step 3) — it never writes .git/index:

  base=\$(git rev-parse HEAD)
  export GIT_INDEX_FILE=\"\$(git rev-parse --git-dir)/gene-index\"
  git read-tree \"\$base\" && git add -- <paths> && tree=\$(git write-tree)
  unset GIT_INDEX_FILE
  sha=\$(git commit-tree \"\$tree\" -p \"\$base\" -F msg.txt)
  git update-ref HEAD \"\$sha\" \"\$base\"   # fails if another agent committed meanwhile"

  jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
