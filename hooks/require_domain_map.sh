#!/usr/bin/env bash
#
# PreToolUse hook: deny a sweep of the source tree until /project-domain has been
# invoked — the skill that opens the project's domain map, or bootstraps one when the
# project has none. AGENTS.md asks for it first because orientation skipped here is
# paid back as blind searching for the rest of the session.
#
# The SessionStart hook already *names* the map. This is the half that makes it hold:
# injected context is advice a session can walk straight past, the way a persona rule
# only holds because require_persona.sh denies. Same shape, same reason.
#
# Only sweeps are gated. Reading one named file is not blind searching, and gating
# Read would deadlock the gate against its own instruction. The user can bypass for a
# session by replying "skip domain map". Wired globally by install.sh.
#
set -u

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/lib/bash_command.sh"

INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' | strip_heredoc_bodies)"

# What counts as sweeping. The dedicated search tools always do; through Bash only a
# recursive search does, so `grep pattern one_file.dart` stays free. The recursion flag
# is matched wherever it sits in the argument list and in either spelling: a gate you
# disarm by writing `grep -n -r` instead of `grep -rn` is one that will be disarmed by
# accident.
RECURSIVE_GREP='([A-Za-z0-9_./-]*/)?grep([[:space:]][^;&|]*)?[[:space:]](-[A-Za-z]*[rR][A-Za-z]*|--recursive|--dereference-recursive)([[:space:]]|$)'
case "$TOOL" in
  Grep|Glob) ;;
  Bash)
    printf '%s' "$CMD" \
      | grep -qE "(^|[;&|(][[:space:]]*)([A-Za-z0-9_./-]*/)?(rg|ag|fd|find)([[:space:]]|\$)|$RECURSIVE_GREP" \
      || exit 0
    ;;
  *) exit 0 ;;
esac

# Where this call will look, never what it looks *for*. A pattern is not a location:
# `grep -rn "/tmp/" .` searches the whole tree for the text "/tmp/", and reading that
# as a location would wave it through as scratch work. Glob is the exception its own
# API makes — there the pattern *is* the path.
LOCATIONS="$(printf '%s' "$INPUT" | jq -r '
  [ .tool_input.path?,
    .tool_input.glob?,
    (if .tool_name == "Glob" then .tool_input.pattern? else empty end)
  ] | map(select(.)) | join("\n")')
$(printf '%s\n' "$CMD" | sweep_paths)"

# Scratch space and the CLI's own state are not the product's source tree.
printf '%s' "$LOCATIONS" | grep -qE "$SCRATCH_PATH|/\.claudita/|/\.claude/projects/" && exit 0

PROJECT="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty')}"
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || exit 0
ROOT="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

MAP="$(domain_map_path "$ROOT")"

# A filename is a regex full of dots. Escape it once, here, rather than trusting every
# later grep -E to be the one that used -F.
#
# Searching *the map itself* — the pd:* anchor index the skill sends you to — is what
# the gate asks for, never what it blocks. Searching the tree *for mentions of* the map
# is an ordinary sweep, which is why this reads locations and not the pattern.
if [ -n "$MAP" ]; then
  BASE_RE="$(basename "$MAP" | sed 's/[.[\*^$+?(){}|]/\\&/g')"
  printf '%s' "$LOCATIONS" | grep -qE "(^|/)$BASE_RE\$" && exit 0
fi

# The user's own escape hatch, for the docs-only and pure-infra sessions a hook can't
# recognize by itself — and, in the same pass, the user typing /project-domain. Only a
# genuine human turn counts, and GENUINE_USER_TEXT reduces a typed slash command to
# the name they typed, so the skill's own instructions can never speak for them.
jq -rR "$GENUINE_USER_TEXT" "$TRANSCRIPT" 2>/dev/null \
  | grep -qiE 'skip domain[ -]?map|/project-domain' && exit 0

# The skill, actually invoked — the only move that lifts this gate. Read from the
# parsed field, never by grepping the transcript whole: this hook and its tests
# necessarily quote the strings they trigger on, so a session that writes them would
# unlock itself.
#
# Opening the map by hand deliberately does not count. When it did, the gate undid
# itself: a session cat's the map, the gate falls away, and it goes back to one file
# per call having never met the anchor index that would have told it which file to
# open. The map is the content; the skill is the method for reaching into it and the
# duty to leave it current, and only the skill carries those.
jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
    | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' \
  "$TRANSCRIPT" 2>/dev/null | grep -qx 'project-domain' && exit 0

CALL='Invoke the project-domain skill now — Skill(skill: "project-domain"). The user can also type /project-domain.'
WAIVER="Dropping to one cat per file instead is the blind searching this gate exists to stop, not a way past it. If this is docs-only or pure infra/CI work, the user can reply 'skip domain map'."

if [ -n "$MAP" ]; then
  REASON="Domain-map gate (AGENTS.md): the project-domain skill has not run this session, so this sweep is blind searching.

$CALL

It opens $MAP and works the pd:* anchor index that names the file you want. Nothing else lifts this gate — reading the map yourself does not, because the map is where things live and the skill is how to reach them and how to leave the map current.

$WAIVER"
else
  REASON="Domain-map gate (AGENTS.md): $ROOT has no domain map, so there is nothing to orient from and this sweep is blind searching.

$CALL

It bootstraps PROJECT_DOMAIN.md from the codebase, and that is what lifts this gate.

$WAIVER"
fi

jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
