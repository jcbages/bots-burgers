#!/usr/bin/env bash
#
# Shared reading of a Bash command, for the hooks that gate on what it does.
# Source this file, then pipe commands (one per line) into the functions below.

# What counts as product source, and what is scratch or build output. `lib/` is
# compiled output for TypeScript but *source* for Dart, so only the compiled path
# is excluded.
SOURCE_EXT='(rb|erb|js|jsx|ts|tsx|mjs|cjs|vue|svelte|py|go|rs|java|kt|swift|c|cc|cpp|h|hpp|cs|php|ex|exs|scss|css|sql|dart)'
SCRATCH_PATH='mktemp|/(private/)?tmp/|/var/folders/|/scratchpad/'
NON_SOURCE_PATH="$SCRATCH_PATH"'|/node_modules/|functions/lib/'

# A heredoc body is data being written, not commands being run. Every gate here
# matches on text, so a body quoting a gated command must not read as running it.
# The opening line is kept: it carries the redirect naming the write target.
#
# An opener is only a heredoc when its delimiter ends the command word — otherwise
# `echo "a << b"` and Ruby's `<<` would open a phantom body that swallows the rest
# of the command. A `<<-` opener allows the terminator to be indented with tabs.
strip_heredoc_bodies() {
  awk '
    function terminates(line) {
      if (dash) { sub(/^[ \t]+/, "", line) }
      return line == delim
    }
    inbody == 1 { if (terminates($0)) { inbody = 0 } ; next }
    {
      print
      if (match($0, /<<-?[ \t]*([\047][A-Za-z_][A-Za-z0-9_]*[\047]|"[A-Za-z_][A-Za-z0-9_]*"|[A-Za-z_][A-Za-z0-9_]*)[ \t]*($|[>|&;])/)) {
        opener = substr($0, RSTART, RLENGTH)
        dash = (opener ~ /^<<-/)
        sub(/^<<-?[ \t]*/, "", opener)
        sub(/[ \t]*[>|&;]?$/, "", opener)
        gsub(/[\047"]/, "", opener)
        delim = opener
        inbody = 1
      }
    }'
}

# Quotes around a path are the normal way to write one, and must not hide it.
_unquote() { tr -d '\047"'; }

# `a && b ; c | d` is several commands. An in-place editor's target is the last
# argument of *its own* segment, not of whatever ran after it.
_segments() { tr ';|&' '\n\n\n'; }

# The source files these commands write. Reads, greps, and paths merely quoted
# inside a heredoc body are not writes and must not appear.
source_write_targets() {
  local commands
  commands="$(strip_heredoc_bodies | _unquote)"
  {
    # Redirects and tee: the target follows the operator.
    printf '%s\n' "$commands" \
      | grep -oE "(>>?|[[:space:]]tee([[:space:]]+-a)?)[[:space:]]*[A-Za-z0-9_./-]+\.$SOURCE_EXT([[:space:]]|$)" \
      | grep -oE "[A-Za-z0-9_./-]+\.$SOURCE_EXT"
    # In-place editors and copies: the target is the last argument of the segment.
    printf '%s\n' "$commands" | _segments \
      | grep -E '(sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|^[[:space:]]*(cp|mv)[[:space:]])' \
      | awk '{print $NF}' | grep -E "\.$SOURCE_EXT$"
  } 2>/dev/null \
    | grep -vE "$NON_SOURCE_PATH" \
    || true
}

# Where a git invocation in this command actually runs: an explicit -C, else a
# directory cd'd into beforehand, else empty (meaning the session's own cwd). Text
# elsewhere in the command — a commit message, a later clause — is not a location.
git_working_dir() {
  local cmd; cmd="$(cat | _unquote)"
  local dir
  dir="$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}')"
  [ -n "$dir" ] && { printf '%s' "$dir"; return; }
  local before
  before="$(printf '%s' "$cmd" | sed -E 's/([A-Za-z0-9_./-]*\/)?git[[:space:]]+([^;&|]*[[:space:]])?commit.*//')"
  printf '%s' "$before" | grep -oE '(^|[;&|(][[:space:]]*)cd[[:space:]]+[^[:space:]]+' | tail -1 | awk '{print $NF}'
}

# The provenance filter every transcript scan needs. Role is not provenance: hook
# feedback, subagent reports, slash-command echoes, command output and a gate's own
# denial are all stored with role "user". A gate that trusts the role licenses
# itself off its own message. One copy, because two drift.
GENUINE_USER_TEXT='fromjson? // empty
  | select(.message.role=="user" and .isMeta != true)
  | ( if (.message.content|type)=="string" then .message.content
      else ([.message.content[]? | select(.type=="text") | .text] | join("\n")) end )
  | select(test("^[[:space:]]*<(task-notification|command-name|command-message|local-command-|system-reminder)") | not)
  | select(test("SYSTEM NOTIFICATION - NOT USER INPUT") | not)
  | select(length > 0)'

# The user asking for a commit, and only the user. Composed here rather than at the
# call site because every layer of shell quoting around a jq regex is a place to
# lose a backslash.
COMMIT_CONSENT_FILTER="$GENUINE_USER_TEXT
  | select(test(\"Explicit-commit gate\") | not)
  | select(test(\"(?i)(\\\\bcommit\\\\b|\\\\bamend\\\\b|/gene\\\\b|\\\\bship it\\\\b|\\\\bland (it|this)\\\\b)\"))"

# Is this path product source? Used by the gates that must treat an Edit tool call
# and a Bash redirect to the same file as the same act.
is_source_path() {
  printf '%s' "$1" | grep -qE "\.$SOURCE_EXT$" || return 1
  printf '%s' "$1" | grep -qvE "$NON_SOURCE_PATH"
}
