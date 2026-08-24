#!/usr/bin/env bash
#
# SessionStart hook: point Claude at the project's domain map before it starts
# grepping. Orientation is injected rather than left to a skill description to pick
# up, the same way the persona is. Wired globally by install.sh (see merge_settings).
#
set -u

INPUT="$(cat)"
CWD="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty')}"
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

MAP=""
for candidate in "$ROOT/PROJECT_DOMAIN.md" "$ROOT/.claude/PROJECT_DOMAIN.md"; do
  [ -f "$candidate" ] && MAP="$candidate" && break
done

# A project may name its own map in CLAUDE.md (e.g. Kerni's KERNI_DOMAIN.md).
if [ -z "$MAP" ] && [ -f "$ROOT/CLAUDE.md" ]; then
  NAMED="$(grep -oE '[A-Z_]+_DOMAIN\.md' "$ROOT/CLAUDE.md" | head -1)"
  [ -n "$NAMED" ] && [ -f "$ROOT/$NAMED" ] && MAP="$ROOT/$NAMED"
fi

if [ -n "$MAP" ]; then
  CONTEXT="Domain map: $MAP. Read it before any Grep/Glob/Read sweep of the source tree — it names the file you want. If this session materially changes what it describes, update it in the same change."
else
  CONTEXT="No domain map exists in $ROOT. Before the first Grep/Glob/Read sweep of the source tree, invoke /project-domain to bootstrap PROJECT_DOMAIN.md — orientation you skip here is paid back as blind searching for the rest of the session. Skip only for docs-only or pure infra/CI work."
fi

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
