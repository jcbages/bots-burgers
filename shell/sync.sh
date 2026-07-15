#!/usr/bin/env bash
#
# Auto-commit (and push, if a remote exists) the ai-config repo when it changed.
# Wired as a Claude Code "Stop" hook so edits to the global config are persisted.
# Runs on every session stop but is a no-op when nothing changed. Never blocks the
# session: push failures (offline, auth) are swallowed.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

git add -A
if git diff --cached --quiet; then
  exit 0
fi

git commit -q -m "Auto-sync config ($(date '+%Y-%m-%d %H:%M:%S'))"

if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin HEAD 2>/dev/null || true
fi
