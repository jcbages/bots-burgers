#!/usr/bin/env bash
#
# Per-session record of what THIS session changed, in a working tree that many
# sessions share.
#
# A shared working tree destroys authorship: once two agents have written to a
# file it is one blob, and no after-the-fact analysis can say which lines came
# from whom. So authorship has to be recorded as it happens. For each file a
# session touches we keep two blobs:
#
#   origin  the file as it stood when this session first touched it
#   shadow  origin plus ONLY this session's edits
#
# A tool call's own delta is pre->post around that call; folding it into shadow
# with a 3-way merge leaves everyone else's work out, because their edits are in
# both pre and post and so cancel. `git diff origin shadow` is then this
# session's change, and merging origin->shadow onto HEAD is its commit.
#
# 3-way merge rather than a stored patch: a patch goes stale the moment another
# session shifts the line numbers, and fails where a merge absorbs the shift and
# reports a real conflict as a conflict.

set -u

# Where this session's ledger lives. Repo-local, so a clone is not polluted.
# Memoized: both the getter and the setter read it once per tracked path, and a
# `git rev-parse` per call is most of what this hook costs.
ledger_dir() {
  if [ -z "${_LEDGER_DIR:-}" ]; then
    local gd sid
    gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
    sid="${LEDGER_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
    [ -n "$sid" ] || return 1
    _LEDGER_DIR="$gd/agent-ledger/$sid"
  fi
  printf '%s' "$_LEDGER_DIR"
}

ledger_state() { printf '%s/state' "$(ledger_dir)"; }

# Every path differing from HEAD, tracked or not. quotePath off so a non-ASCII
# name arrives as itself; a newline in a filename is out of scope and would need
# -z parsing everywhere it is read.
_ledger_changed_paths() {
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || return 0
  { git -c core.quotePath=false diff --name-only HEAD 2>/dev/null
    git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
}

# "path<TAB>blob" for each changed path; blob is "-" when the file is gone.
# One hash-object for the whole set — a process per file is the difference
# between a hook you keep and one you turn off.
ledger_snapshot() {
  local all exist
  all="$(_ledger_changed_paths)"
  [ -n "$all" ] || return 0
  exist="$(printf '%s\n' "$all" | while IFS= read -r p; do [ -e "$p" ] && printf '%s\n' "$p"; done)"
  [ -n "$exist" ] && paste -d'	' \
    <(printf '%s\n' "$exist") \
    <(printf '%s\n' "$exist" | git hash-object -w --stdin-paths)
  printf '%s\n' "$all" | while IFS= read -r p; do [ -e "$p" ] || printf '%s\t-\n' "$p"; done
}

# HEAD's version of a path, or "-" when HEAD has no such file.
_ledger_head_blob() { git rev-parse -q --verify "HEAD:$1" 2>/dev/null || printf -- '-'; }

_ledger_is_binary() {
  [ "$1" = "-" ] && return 1
  ! git cat-file -p "$1" 2>/dev/null | perl -ne 'exit 1 if /\0/'
}

_ledger_blob_to() { # <sha|-> <file>
  if [ "$1" = "-" ]; then : > "$2"; else git cat-file -p "$1" > "$2" 2>/dev/null || : > "$2"; fi
}

# Incorporate base->other into current. Echoes the resulting blob, and returns
# non-zero on conflict WITHOUT echoing — a shadow must never hold conflict
# markers, because it is committed verbatim.
ledger_merge3() { # <current> <base> <other>
  local d rc
  d="$(mktemp -d)"
  _ledger_blob_to "$1" "$d/cur"; _ledger_blob_to "$2" "$d/base"; _ledger_blob_to "$3" "$d/oth"
  git merge-file -q "$d/cur" "$d/base" "$d/oth" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && git hash-object -w "$d/cur"
  rm -rf "$d"
  [ "$rc" -eq 0 ]
}

# state is TSV: path, origin, shadow, status ("ok" or "contested").
ledger_get() { # <path> -> "origin<TAB>shadow<TAB>status", empty if not this session's
  local s; s="$(ledger_state)"
  [ -f "$s" ] || return 0
  awk -F'\t' -v p="$1" '$1==p {print $2 "\t" $3 "\t" $4; exit}' "$s"
}

ledger_put() { # <path> <origin> <shadow> <status>
  local s d tmp; s="$(ledger_state)"; d="$(ledger_dir)"
  mkdir -p "$d"
  tmp="$s.tmp.$$"
  { [ -f "$s" ] && awk -F'\t' -v p="$1" '$1!=p' "$s"; printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; } > "$tmp"
  mv "$tmp" "$s"
  _ledger_anchor
}

ledger_contested() { # paths this session could not cleanly separate
  local s; s="$(ledger_state)"
  [ -f "$s" ] && awk -F'\t' '$4=="contested" {print $1}' "$s" || true
}

ledger_drop() { # <path...>
  local s tmp p; s="$(ledger_state)"; [ -f "$s" ] || return 0
  tmp="$s.tmp.$$"; cp "$s" "$tmp"
  for p in "$@"; do awk -F'\t' -v p="$p" '$1!=p' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"; done
  mv "$tmp" "$s"
  _ledger_anchor
}

ledger_paths() { local s; s="$(ledger_state)"; [ -f "$s" ] && cut -f1 "$s" || true; }

# `git hash-object -w` leaves the blobs unreachable, and `git gc --prune=now`
# would take a session's whole record with it. One ref holds them all.
_ledger_anchor() {
  local s sid tree n=0 line
  s="$(ledger_state)"; [ -f "$s" ] || return 0
  sid="${LEDGER_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
  tree="$(while IFS=$'\t' read -r _ o sh _; do
            for b in "$o" "$sh"; do
              [ "$b" = "-" ] && continue
              printf '100644 blob %s\t%s\n' "$b" "b$n"; n=$((n+1))
            done
          done < "$s" | sort -u -k4 | git mktree 2>/dev/null)"
  [ -n "$tree" ] && git update-ref "refs/agent-ledger/$sid" "$tree" 2>/dev/null || true
}
