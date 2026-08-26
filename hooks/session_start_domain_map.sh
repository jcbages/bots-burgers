#!/usr/bin/env bash
#
# SessionStart hook: point Claude at the project's domain map before it starts
# grepping. Orientation is injected rather than left to a skill description to pick
# up, the same way the persona is. Wired globally by install.sh (see merge_settings).
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

INPUT="$(cat)"
CWD="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty')}"
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

MAP="$(domain_map_path "$ROOT")"

if [ -n "$MAP" ]; then
  CONTEXT="Domain map: $MAP. Invoke /project-domain before sweeping the source tree — it opens the map and works the pd:* anchor index that names the file you want. require_domain_map.sh denies the first Grep/Glob/recursive-grep until that skill has run, and opening the map by hand does not lift it, so invoking it now is cheaper than being turned back. If this session materially changes what the map describes, update it in the same change."
else
  CONTEXT="No domain map exists in $ROOT. Invoke /project-domain to bootstrap PROJECT_DOMAIN.md before sweeping the source tree — orientation you skip here is paid back as blind searching for the rest of the session, and require_domain_map.sh denies the first sweep until it exists. Skip only for docs-only or pure infra/CI work, which the user waives with 'skip domain map'."
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
