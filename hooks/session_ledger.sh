#!/usr/bin/env bash
#
# PreToolUse/PostToolUse hook (Bash|Edit|Write|NotebookEdit): record what THIS
# session changed, so it can later commit exactly that and nothing else.
#
# Called as `session_ledger.sh pre` before a tool call and `... post` after. The
# delta between the two snapshots is what that one call did — anything another
# session wrote beforehand sits in both snapshots and cancels out. The window is
# one tool call; a write landing inside it is the one case this cannot separate,
# which is why `bin/mine` exists to be read before committing.
#
# Wired globally by install.sh (see merge_settings).
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/ledger.sh
. "$REPO_DIR/lib/ledger.sh"

MODE="${1:-}"
# One jq, not two: this runs before and after every tool call, so every process
# spawned here is paid twice for each action the session takes.
IFS=$'\t' read -r SID CWD TID < <(jq -r '[.session_id // "", .cwd // "", .tool_use_id // "one"] | @tsv' 2>/dev/null)
[ -n "${SID:-}" ] && export LEDGER_SESSION="$SID"
[ -n "${CWD:-}" ] && cd "$CWD" 2>/dev/null

D="$(ledger_dir)" || exit 0     # not a git repo, or no session id — nothing to record
mkdir -p "$D"

# Keyed per tool call, because a session can have two in flight at once (a
# background Bash and a foreground edit) and a single pre-snapshot would be
# overwritten by whichever started second. Falls back to one shared slot when the
# payload carries no id, which is the older behaviour rather than a new failure.
PRE="$D/pre.${TID:-one}"

# Fold one call's delta into this session's shadows.
_fold() {
  local pre="$1" post="$2"
  cut -f1 "$pre" "$post" 2>/dev/null | sort -u | while IFS= read -r p; do
    [ -n "$p" ] || continue
    local b_pre b_post cur origin shadow status new
    # A snapshot lists only what differs from HEAD, so a path missing from one is
    # a file that matched HEAD at that moment — not a file that did not exist.
    # Reading the first as the second makes every first edit look like a creation.
    b_pre="$(awk -F'\t' -v p="$p" '$1==p{print $2; exit}' "$pre")"
    b_post="$(awk -F'\t' -v p="$p" '$1==p{print $2; exit}' "$post")"
    [ -n "$b_pre" ]  || b_pre="$(_ledger_head_blob "$p")"
    [ -n "$b_post" ] || b_post="$(_ledger_head_blob "$p")"
    [ "$b_pre" = "$b_post" ] && continue          # this call did not touch it

    cur="$(ledger_get "$p")"
    if [ -z "$cur" ]; then
      origin="$b_pre"; shadow="$b_pre"; status=ok  # first touch: baseline is what was there
    else
      IFS=$'\t' read -r origin shadow status <<< "$cur"
    fi

    if [ "$b_post" = "-" ] || [ "$shadow" = "-" ] || _ledger_is_binary "$b_post"; then
      new="$b_post"                                # deletion, creation, or unmergeable
    elif new="$(ledger_merge3 "$shadow" "$b_pre" "$b_post")"; then
      :
    else
      new="$shadow"; status=contested              # overlaps someone else's edit
    fi
    ledger_put "$p" "$origin" "$new" "$status"
  done
}

case "$MODE" in
  pre)  ledger_snapshot > "$PRE" 2>/dev/null ;;
  post) [ -f "$PRE" ] || exit 0
        ledger_snapshot > "$PRE.post" 2>/dev/null
        _fold "$PRE" "$PRE.post"
        rm -f "$PRE" "$PRE.post" ;;
esac
exit 0
