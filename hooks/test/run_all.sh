#!/usr/bin/env bash
#
# Runs every hook suite. Run: hooks/test/run_all.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0

for suite in "$DIR"/*_test.sh; do
  printf '\n═══ %s ═══\n' "$(basename "$suite")"
  bash "$suite" || failed=1
done

printf '\n%s\n' "$([ "$failed" -eq 0 ] && echo 'all suites green' || echo 'SUITES FAILED')"
exit "$failed"
