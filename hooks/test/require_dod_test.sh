#!/usr/bin/env bash
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
output="$(printf '%s' '{"cwd":"/proj","transcript_path":"/missing"}' | "$DIR/../require_dod.sh")"
[ -z "$output" ]
printf '  ok   legacy require_dod stays silent without prerequisites\n'
