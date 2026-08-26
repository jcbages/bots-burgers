#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny `git commit` unless the user asked for it, and treat
# that request as spent once a commit uses it. Committing is the user's call and the
# moment they want a summary, so the denial hands back the handoff report instead
# (see AGENTS.md "Handing off"). Wired globally by install.sh (see merge_settings).
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' | strip_heredoc_bodies)"

# Only gate commits. Amend, fixup and the `commit-tree`/`update-ref` plumbing all
# count — see GIT_COMMIT_RE. Every other git command is free. The binary may be
# reached by path, so `git` is not necessarily the first word.
printf '%s' "$CMD" | grep -qE "$GIT_COMMIT_RE" || exit 0

# A commit in scratch space is a test fixture, not the user's history. This asks
# where git actually runs — a commit *message* mentioning /tmp is not a location.
GIT_DIR="$(printf '%s\n' "$CMD" | git_working_dir)"
if [ -n "$GIT_DIR" ] && printf '%s' "$GIT_DIR" | grep -qE "$SCRATCH_PATH"; then
  exit 0
fi

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# The user's latest word decides. A request stands while it is the last thing they
# said — long enough to commit what that request covers, across more than one repo if
# it takes that — and ends the moment they say anything else. No stored state, so
# nothing to go stale and no clock to get wrong: the transcript already holds the
# answer. Role is not provenance here, which is what GENUINE_USER_TEXT settles.
LAST_SPOKEN="$(jq -rR "$GENUINE_USER_TEXT
  | select(test(\"commit gate \\\\(AGENTS\\\\.md\\\\)\") | not)" "$TRANSCRIPT" 2>/dev/null | tail -1)"

printf '%s' "$LAST_SPOKEN" | grep -qiE "$COMMIT_REQUEST_RE" && exit 0

REASON="Explicit-commit gate (AGENTS.md): the user has not asked for a commit since the last one. Committing is theirs to trigger.

Instead, hand off — list the files this session touched with one line each on *why*, name anything deliberately left out, and stop. If they want it committed they will say so, or run /gene.

If they already asked and this fired anyway, say so; do not retry the command."

jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
