#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny the git commands that throw working-tree content
# away. Every agent in this tree edits the same files at the same time, and
# `git checkout -- .`, `git restore`, `git reset --hard`, `git stash` and
# `git clean -f` all operate on the tree rather than on your diff — so they delete
# whatever another session had in flight, with no reflog and no blob to get it back
# from. Scoping a commit protects someone else's history; this protects their work.
# A linked worktree is nobody else's, so it is exempt. Wired globally by install.sh.
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

PAYLOAD="$(cat)"
CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' | strip_heredoc_bodies)"
HERE="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty')"

# Each offending segment reports the directory it runs in, because an exemption one
# segment earns is not the next one's: `git -C <worktree> status && git reset --hard`
# resets the shared tree. A `checkout` naming one path is git's own DWIM — branch or
# pathspec is decided by the filesystem, so the argument comes back for that test.
FINDINGS="$(printf '%s' "$CMD" | _unquote \
  | awk '{ gsub(/`/, " \a$ "); gsub(/\(/, "\n\a(\n"); gsub(/\)/, "\n\a)\n"); print }' | _segments | awk '
  # The subcommands are a closed set, unlike the things that can precede a command, so
  # a candidate whose verb is not one of them is a word that merely looks like git.
  BEGIN { SUB = "^(checkout|switch|restore|reset|stash|clean|commit|add|status|log|diff|show|push|pull|fetch|merge|rebase|branch|tag|worktree|config|remote|rev-parse|ls-files|grep|apply|cherry-pick|revert|init|clone|submodule|describe|blame|bisect|reflog|mv|rm)$" }
  # A cd dies with the subshell that made it, so the location it set must too.
  $1 == "\a(" { saved[++depth] = pending; next }
  $1 == "\a)" { if (depth > 0) pending = saved[depth--]; next }
  {
    # What can stand in front of a command is an endless list — sudo, xargs, eval,
    # find -exec, a loop keyword, an env assignment. What spends its arguments on
    # text rather than commands is a short one, so find the git token anywhere and
    # let those ten speak for the segment instead. A substitution is not text: it runs.
    quoting = 0; seen = 0; insub = 0; runs = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "cd") pending = $(i + 1)
      if ($i == "\a$") { insub = !insub; continue }
      if (!seen && $i ~ /^(echo|printf|grep|egrep|fgrep|rg|ag|sed|awk|cat)$/) quoting = 1
      if ($i ~ /(^|\/)git$/) { seen = 1; if (insub) runs = 1 }
    }
    if ((quoting && !runs) || !seen) next
    # Every candidate gets parsed, not just the first: a directory named git matches
    # the same pattern as the binary, and would otherwise shadow the real invocation.
    for (g = 1; g <= NF; g++) {
      if ($g !~ /(^|\/)git$/) continue
      verb = ""; n = 0; dashdash = 0; flags = ""; loc = ""; delete arg
      for (j = g + 1; j <= NF; j++) {
        # A global option that takes a separate value would otherwise donate it to the
        # verb slot, sliding the real subcommand into arg[1] where no rule looks.
        if ($j ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--exec-path)$/) {
          if ($j == "-C") loc = $(j + 1)
          j++; continue
        }
        if ($j == "--") { dashdash = 1; continue }
        if (substr($j, 1, 1) == "-") { flags = flags " " $j; continue }
        if (verb == "") { verb = $j; continue }
        arg[++n] = $j
      }
      if (verb !~ SUB) continue
      where = (loc != "" ? loc : pending)
      # A short flag travels in a cluster (-fd), a long one alone (--force).
      force = (flags ~ /(^| )-[a-zA-Z]*f/ || flags ~ / --force( |$)/)
      creates = (flags ~ /(^| )-[a-zA-Z]*[bB]( |$)/ || flags ~ / --(create|force-create)( |$)/)
      # `$(` cut this record in half, so the pathspec that decides it is in another
      # one. A seam is not an argument: never grant the DWIM allowance across it.
      seam = (arg[1] ~ /\$$/ || arg[1] == "\a$")
      if (verb == "checkout") {
        if (dashdash || n >= 2 || force || seam || arg[1] ~ /^\.\.?(\/|$)/) print where "\t"
        else if (n == 1 && !creates) print where "\t" arg[1]
      }
      if (verb == "switch" && (force || flags ~ / --discard-changes( |$)/)) print where "\t"
      if (verb == "restore" && !(flags ~ /(^| )(-[a-zA-Z]*S|--staged)( |$)/ \
          && flags !~ /(^| )(-[a-zA-Z]*W|--worktree)( |$)/)) print where "\t"
      if (verb == "reset" && flags ~ / --(hard|merge|keep)( |$)/) print where "\t"
      if (verb == "stash" && (n == 0 || arg[1] ~ /^(push|save)$/)) print where "\t"
      if (verb == "clean" && (force || flags ~ /(^| )-[a-zA-Z]*[dx]/) \
          && !(flags ~ /(^| )-[a-zA-Z]*n/ || flags ~ / --dry-run( |$)/)) print where "\t"
      # This candidate was the invocation; what follows it is its own data.
      break
  }
  }')"

[ -n "$FINDINGS" ] || exit 0

# git reports --git-common-dir relative to its own cwd, so the two paths must be
# asked for in the same format or a subdirectory reads as a linked worktree.
is_shared_tree() { # <dir>
  printf '%s' "$1" | grep -qE "$SCRATCH_PATH" && return 1
  local dirs
  dirs="$(git -C "$1" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)"
  [ "$(printf '%s' "$dirs" | head -1)" = "$(printf '%s' "$dirs" | tail -1)" ]
}

resolve() { # <path> <base>
  case "$1" in
    "~"*) printf '%s' "$HOME${1#\~}" ;;
    /*)   printf '%s' "$1" ;;
    *)    printf '%s' "$2/$1" ;;
  esac
}

# Splitting by hand: a tab is IFS whitespace, so `read` would collapse an empty
# first field and hand the DWIM argument back as the directory.
TAB="$(printf '\t')"
while IFS= read -r finding; do
  where="${finding%%"$TAB"*}"
  dwim="${finding#*"$TAB"}"
  dir="$(resolve "${where:-.}" "${HERE:-.}")"
  [ -n "$dwim" ] && [ ! -e "$(resolve "$dwim" "$dir")" ] && continue
  is_shared_tree "$dir" || continue
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Discard gate (AGENTS.md): this discards working-tree content, and other agents are editing files in this tree right now — their uncommitted lines would be gone with no reflog to recover them. To undo your own edit, edit the file back (the session ledger tracks it) or commit and revert the commit. If the tree really does need resetting, ask the user to run it."}}
JSON
  exit 0
done <<< "$FINDINGS"
