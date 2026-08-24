#!/usr/bin/env bash
#
# Stop hook: report uncommitted ai-config changes; never commit them. Committing is
# the user's call here for the same reason the PreToolUse commit gate enforces it
# everywhere else — and a hook that committed on every stop would fragment one change
# across however many times the session happened to end.
#
set -eu

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

CHANGED="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
[ "$CHANGED" = "0" ] && exit 0

FILES="$(git status --porcelain | awk '{print $NF}' | head -8 | paste -sd',' - | sed 's/,/, /g')"
[ "$CHANGED" -gt 8 ] && FILES="$FILES, +$((CHANGED - 8)) more"

AHEAD="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
UNPUSHED=""
[ "$AHEAD" != "0" ] && UNPUSHED=" $AHEAD commit(s) unpushed."

jq -n --arg m "ai-config has $CHANGED uncommitted file(s): $FILES.$UNPUSHED Commit when you're ready — auto-commit is off." \
  '{systemMessage: $m}'
