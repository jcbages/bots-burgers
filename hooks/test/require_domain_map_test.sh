#!/usr/bin/env bash
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
output="$(printf '%s' '{"tool_name":"Grep","tool_input":{"pattern":"anything"}}' | "$DIR/../require_domain_map.sh")"
[ -z "$output" ]
printf '  ok   legacy require_domain_map stays silent without prerequisites\n'
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
git -C "$W" init -q
output="$(jq -n --arg cwd "$W" '{cwd:$cwd}' | CLAUDE_PROJECT_DIR="$W" "$DIR/../session_start_domain_map.sh")"
[ -z "$output" ]
printf '  ok   missing map does not request bootstrap\n'
printf '# Domain map\n' > "$W/PROJECT_DOMAIN.md"
output="$(jq -n --arg cwd "$W" '{cwd:$cwd}' | CLAUDE_PROJECT_DIR="$W" "$DIR/../session_start_domain_map.sh")"
printf '%s' "$output" | jq -e --arg path "$W/PROJECT_DOMAIN.md" '.hookSpecificOutput.additionalContext | contains($path)' >/dev/null
if printf '%s' "$output" | grep -qiE 'must|invoke|bootstrap|denies'; then exit 1; fi
printf '  ok   existing map is an optional location hint\n'
