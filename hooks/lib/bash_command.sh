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

# The spellings that write history. `git commit-tree` builds a commit and
# `git update-ref` moves the branch onto it, so a gate matching the bare word
# `commit` waves the two-step plumbing form through untouched. One copy, because
# two drift.
GIT_COMMIT_VERB='(commit(-tree)?|update-ref)'
_GIT_COMMIT="([A-Za-z0-9_./-]*/)?git[[:space:]]+([^;&|]*[[:space:]])?$GIT_COMMIT_VERB"
# `commit-mine` writes history too — it is the sanctioned way to do it here, which
# is exactly why it must not be the way around the gate.
GIT_COMMIT_RE="(^|[;&|[:space:]])($_GIT_COMMIT|([A-Za-z0-9_./-]*/)?commit-mine)([[:space:]]|\$)"

# Where a git invocation in this command actually runs: an explicit -C, else a
# directory cd'd into beforehand, else empty (meaning the session's own cwd). Text
# elsewhere in the command — a commit message, a later clause — is not a location.
git_working_dir() {
  local cmd; cmd="$(cat | _unquote)"
  local dir
  dir="$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}')"
  [ -n "$dir" ] && { printf '%s' "$dir"; return; }
  local before
  before="$(printf '%s' "$cmd" | sed -E "s#([A-Za-z0-9_./-]*/)?git[[:space:]]+([^;&|]*[[:space:]])?$GIT_COMMIT_VERB.*##")"
  printf '%s' "$before" | grep -oE '(^|[;&|(][[:space:]]*)cd[[:space:]]+[^[:space:]]+' | tail -1 | awk '{print $NF}'
}

# The provenance filter every transcript scan needs. Role is not provenance: hook
# feedback, subagent reports, command output and a gate's own denial are all stored
# with role "user". A gate that trusts the role licenses itself off its own message.
# One copy, because two drift.
#
# Typing a slash command IS the user speaking, so an echo of one is kept — but only
# through the command it names and the arguments they typed. Nothing else the echo
# carries survives, so a skill whose instructions merely discuss an action can never
# be read as the user asking for it.
GENUINE_USER_TEXT='fromjson? // empty
  | select(.message.role=="user" and .isMeta != true)
  | ( if (.message.content|type)=="string" then .message.content
      else ([.message.content[]? | select(.type=="text") | .text] | join("\n")) end )
  | select(test("^[[:space:]]*<(task-notification|local-command-|system-reminder)") | not)
  | select(test("SYSTEM NOTIFICATION - NOT USER INPUT") | not)
  | ( if test("^[[:space:]]*<command-(name|message)>")
      then [ scan("<command-(?:name|args)>([^<]*)</command-(?:name|args)>") | .[0] ] | join(" ")
      else . end )
  | select(length > 0)'

# What the user says when they want a commit. A grep pattern rather than a jq one:
# every layer of shell quoting around a regex is a place to lose a backslash, and the
# caller greps. The caller also decides *which* turn to match — only their latest, so
# a request spends itself instead of standing for the rest of the session.
COMMIT_REQUEST_RE='(\bcommit\b|\bamend\b|/gene\b|\bship it\b|\bland (it|this)\b)'

# The paths a search command will actually visit, one per line. Position is what
# separates them from the pattern: a content searcher spends its first non-flag word on
# what to match and the rest on where, so `grep -rn "/tmp/" .` yields "." and not
# "/tmp/". A caller that flattens the two together inherits both meanings.
sweep_paths() {
  _segments | awk '
    {
      tool = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^([A-Za-z0-9_.\/-]*\/)?(grep|rg|ag|fd|find)$/) { tool = i; break }
      }
      if (tool == 0) next
      # find and fd take a path first; grep, rg and ag spend a word on the pattern.
      pending = ($tool ~ /(find|fd)$/) ? 0 : 1
      for (i = tool + 1; i <= NF; i++) {
        if (substr($i, 1, 1) == "-") continue
        if (pending) { pending = 0; continue }
        print $i
      }
    }'
}

# Where a project keeps its domain map, looked up in the order the /project-domain
# skill looks: the repo root, then .claude/, then whatever name the project's
# CLAUDE.md gives it (Kerni calls its own KERNI_DOMAIN.md — honor that rather than
# creating a second map). Empty output means the project has no map yet.
domain_map_path() { # <repo root>
  local root="$1" candidate named
  for candidate in "$root/PROJECT_DOMAIN.md" "$root/.claude/PROJECT_DOMAIN.md"; do
    [ -f "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  [ -f "$root/CLAUDE.md" ] || return 0
  named="$(grep -oE '[A-Z_]+_DOMAIN\.md' "$root/CLAUDE.md" | head -1)"
  [ -n "$named" ] && [ -f "$root/$named" ] && printf '%s' "$root/$named"
  return 0
}

# Is this path product source? Used by the gates that must treat an Edit tool call
# and a Bash redirect to the same file as the same act.
is_source_path() {
  printf '%s' "$1" | grep -qE "\.$SOURCE_EXT$" || return 1
  printf '%s' "$1" | grep -qvE "$NON_SOURCE_PATH"
}
