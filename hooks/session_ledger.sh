#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-}"
INPUT="$(cat)"
printf '%s' "$INPUT" | python3 "$DIR/lib/ledger_capture.py" "$MODE" || true
