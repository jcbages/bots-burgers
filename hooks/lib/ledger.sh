#!/usr/bin/env bash
# Stores only edits reconstructed from explicit tool inputs and confirmed on disk.

set -u

# The git dir and the work tree, in one rev-parse and once per process: a
# process spawned here is paid twice for every action the session takes.
_ledger_resolve() {
  [ -n "${_LEDGER_ROOT:-}" ] && return 0
  local out
  out="$(git rev-parse --absolute-git-dir --show-toplevel 2>/dev/null)" || return 1
  _LEDGER_GITDIR="${out%%$'\n'*}"
  _LEDGER_ROOT="${out#*$'\n'}"
  [ -n "$_LEDGER_GITDIR" ] && [ -n "$_LEDGER_ROOT" ] &&
    [ "$_LEDGER_GITDIR" != "$_LEDGER_ROOT" ]
}

# Where this session's ledger lives. Repo-local, so a clone is not polluted.
ledger_dir() {
  if [ -z "${_LEDGER_DIR:-}" ]; then
    local sid
    _ledger_resolve || return 1
    sid="${LEDGER_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
    [ -n "$sid" ] || return 1
    _LEDGER_DIR="$_LEDGER_GITDIR/agent-ledger/$sid"
  fi
  printf '%s' "$_LEDGER_DIR"
}

ledger_state() { printf '%s/state' "$(ledger_dir)"; }

# Put the process where git's paths already point. Git reports repo-relative and
# the shell resolves CWD-relative, so a caller running in a subdirectory checks
# every path against the wrong directory, finds nothing, and records the whole
# tree as deleted. Every entry point calls this; nothing here resolves a path
# without it.
ledger_cd_root() {
  _ledger_resolve || return 1
  cd "$_LEDGER_ROOT" || return 1
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

# state is TSV: path, origin, shadow, status ("verified" or "contested").
ledger_get() { # <path> -> "origin<TAB>shadow<TAB>status", empty if not this session's
  local s; s="$(ledger_state)"
  [ -f "$s" ] || return 0
  awk -F'\t' -v p="$1" '$1==p {print $2 "\t" $3 "\t" $4 "\t" $5; exit}' "$s"
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
  [ -f "$s" ] && awk -F'\t' '$4!="verified" {print $1}' "$s" || true
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
