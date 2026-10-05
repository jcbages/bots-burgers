#!/usr/bin/env bash
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
output="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"/proj/app/x.rb"}}' | "$DIR/../require_persona.sh")"
[ -z "$output" ]
printf '  ok   legacy require_persona stays silent without prerequisites\n'
