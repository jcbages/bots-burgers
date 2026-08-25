#!/usr/bin/env bash
#
# Stop hook: block ending a session that edited product code until the transcript
# shows (a) test evidence and (b) a fresh-eyes review by /mr-fischoeder (which
# reviews the local working tree, not just open PRs). This enforces the Definition
# of Done (see AGENTS.md). Language/stack-agnostic: it recognizes the common test
# runners and gates on source-file edits, not Rails-specific paths. The user can
# bypass for a session by replying "skip dod". Wired globally by install.sh.
#
set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKLIST="$REPO_DIR/skills/_shared/bug-checklist.md"

# shellcheck source=hooks/lib/bash_command.sh
. "$REPO_DIR/hooks/lib/bash_command.sh"

INPUT="$(cat)"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
PROJECT="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // empty')}"

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -n "$PROJECT" ] || exit 0

# A gate that can refuse without bound pins a session no action can free. `isMeta`
# separates a refusal the harness replayed from anyone quoting one, and the prefix is
# shared with the message it counts so rewording one cannot silently zero the other.
BLOCK_PREFIX="Definition of Done gate (AGENTS.md): this session edited product code"
MAX_BLOCKS="${DOD_MAX_BLOCKS:-3}"
PRIOR_BLOCKS="$(jq -rR --arg prefix "$BLOCK_PREFIX" 'fromjson? // empty
    | select(.isMeta == true and .message.role == "user")
    | ( if (.message.content|type)=="string" then .message.content
        else ([.message.content[]? | select(.type=="text") | .text] | join("\n")) end )
    | select(contains($prefix))
    | "x"' \
  "$TRANSCRIPT" 2>/dev/null | grep -c x || true)"
if [ "${PRIOR_BLOCKS:-0}" -ge "$MAX_BLOCKS" ] 2>/dev/null; then
  echo "require_dod: blocked ${PRIOR_BLOCKS}x without resolution — releasing the session." >&2
  exit 0
fi

# User override for this session — only a genuine human turn counts. Role is not
# provenance here: this hook's own block message, hook feedback (isMeta), subagent
# reports and slash-command echoes (all <tag>-wrapped) are stored with role "user"
# too. A DoD review subagent necessarily quotes the bypass phrase while doing its
# job, so an unfiltered scan lets the gate disarm itself. Three independent filters,
# so drift in any one doesn't silently reopen the hole.
USER_SAID_SKIP="$(jq -rR 'fromjson? // empty
    | select(.message.role=="user" and .isMeta != true)
    | if (.message.content|type)=="string" then .message.content
      else (.message.content[]? | select(.type=="text") | .text) end
    | select(test("^<(task-notification|command-name|command-message|local-command-|system-reminder)") | not)
    | select(test("Definition of Done gate") | not)' \
  "$TRANSCRIPT" 2>/dev/null \
  | grep -qi 'skip dod' && echo yes || true)"
[ -n "$USER_SAID_SKIP" ] && exit 0

# Gate only sessions that edited product source in this project — by known source
# directory or by source-file extension. Docs/config-only sessions pass through.
EDITED="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
    | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
    | .input.file_path // empty' "$TRANSCRIPT" 2>/dev/null \
  | grep -E "^$PROJECT/" \
  | sed "s|^$PROJECT/||" \
  | grep -vE '\.(md|markdown|txt|lock)$' \
  | grep -E "^(app|lib|src|db|config|test|tests|spec|internal|cmd|pkg|components|server)/|\.$SOURCE_EXT$" \
  || true)"
# Auto mode writes files through Bash, a path the dedicated edit tools never see, so
# both are checked.
BASH_EDITED="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
    | select(.type=="tool_use" and .name=="Bash")
    | .input.command // empty' "$TRANSCRIPT" 2>/dev/null | source_write_targets)"

# A write counts only if it left a file behind. --cwd-relative additionally accepts a
# tail match, for a Bash write named from a directory the session cd'd into; it can
# collide with a deeper file sharing that tail, which MAX_BLOCKS bounds.
surviving_writes() { # [--cwd-relative]
  git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 || { cat; return 0; }
  local loose="${1:-}" present path prefix
  # ls-files answers relative to PROJECT, status always relative to the repo root, so
  # a subdirectory project needs the root prefix stripped to compare them.
  prefix="$(git -C "$PROJECT" rev-parse --show-prefix 2>/dev/null)"
  present="$( { git -C "$PROJECT" ls-files 2>/dev/null
                git -C "$PROJECT" status --porcelain -uall 2>/dev/null |
                  sed 's/^...//; s/.* -> //' | sed "s|^${prefix}||"
              } | sed '/^[[:space:]]*$/d' | sort -u)"
  # `|| [ -n "$path" ]`: the callers printf without a trailing newline, and a bare
  # read drops that last unterminated line — which is usually the only one.
  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -e "$PROJECT/$path" ] || printf '%s\n' "$present" | grep -qxF "$path"; then
      printf '%s\n' "$path"
    elif [ -n "$loose" ] && printf '%s\n' "$present" |
           grep -qE "(^|/)$(printf '%s' "$path" | sed 's/[^A-Za-z0-9_/-]/\\&/g')$"; then
      printf '%s\n' "$path"
    fi
  done
  return 0
}

EDITED="$(printf '%s' "$EDITED" | surviving_writes)"
BASH_EDITED="$(printf '%s' "$BASH_EDITED" | surviving_writes --cwd-relative)"

[ -n "$EDITED" ] || [ -n "$BASH_EDITED" ] || exit 0

TESTS_RAN="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
    | select(.type=="tool_use" and .name=="Bash")
    | .input.command // empty' "$TRANSCRIPT" 2>/dev/null \
  | grep -E '(^|[;&|][[:space:]]*)((bash|sh|zsh)[[:space:]]+|\./)?(bin/ci|(bin/|bundle exec )?rails test|(bin/|bundle exec )?rspec|(npm|pnpm|yarn)( run)? test|jest|vitest|pytest|go test|cargo test|mix test|gradle( |w )test|mvn test|flutter test|dart test|bats|[A-Za-z0-9_./-]*_test\.sh|[A-Za-z0-9_./-]*tests?/[A-Za-z0-9_./-]+\.sh)([[:space:]]|$)' \
  || true)"

REVIEW_RAN="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
    | select(.type=="tool_use")
    | select((.name=="Skill" and .input.skill=="mr-fischoeder")
          or (.name=="Agent" and ((.input.prompt // "") | test("Mr. Fischoeder|bug-checklist"))))
    | .name' "$TRANSCRIPT" 2>/dev/null || true)"

# The user can also invoke the reviewer themselves by typing the slash command,
# which never shows up as a tool_use entry.
if [ -z "$REVIEW_RAN" ] \
   && grep -qE '<command-name>/mr-fischoeder|"(skill|commandName)":"mr-fischoeder"' "$TRANSCRIPT"; then
  REVIEW_RAN="mr-fischoeder"
fi

# The domain map is navigational, so it goes stale when files appear or disappear —
# not when a line inside one changes. Gating every edit would nag the session that
# renamed a string; gating structure catches the ones that move the furniture.
ROOT="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PROJECT")"
MAP="$(domain_map_path "$ROOT")"

STRUCTURAL=""
if [ -n "$MAP" ]; then
  CREATED="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
      | select(.type=="tool_use" and .name=="Write") | .input.file_path // empty' \
    "$TRANSCRIPT" 2>/dev/null | sed "s|^$PROJECT/||" | sort -u || true)"
  REMOVED="$(jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
      | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' \
    "$TRANSCRIPT" 2>/dev/null | strip_heredoc_bodies | _segments \
    | grep -E '(^|[[:space:]])(git[[:space:]]+rm|rm)[[:space:]]' | tr ' ' '\n' \
    | sed "s|^$PROJECT/||" | sort -u || true)"
  # Write overwrites as readily as it creates, so the tool call alone says a file was
  # *touched*, not that it appeared. Only a path git does not already track is new.
  CREATED="$(printf '%s\n' "$CREATED" | while IFS= read -r path; do
    [ -n "$path" ] || continue
    git -C "$PROJECT" ls-files --error-unmatch -- "$path" >/dev/null 2>&1 \
      || printf '%s\n' "$path"
  done)"
  # uniq -u drops what appears in both lists: a file this session created and then
  # deleted leaves no structure behind, the same reason surviving_writes exists.
  STRUCTURAL="$(printf '%s\n%s\n' "$CREATED" "$REMOVED" | sed '/^$/d' | sort | uniq -u \
    | grep -E "\.$SOURCE_EXT$" | grep -vE "$NON_SOURCE_PATH" || true)"
fi

# Only an actual write to the map counts. require_domain_map.sh already forces it to
# be *read*, so crediting a read here would make this condition unreachable.
MAP_UPDATED=""
if [ -n "$STRUCTURAL" ]; then
  jq -rR 'fromjson? // empty | select(.message.content?) | .message.content[]?
      | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="MultiEdit"))
      | .input.file_path // empty' "$TRANSCRIPT" 2>/dev/null \
    | grep -qF "$MAP" && MAP_UPDATED=yes
fi

MISSING=""
[ -z "$TESTS_RAN" ] && MISSING="- Run the touched tests (the stack's test runner — bin/ci, rails test, rspec, npm test, pytest, go test, flutter test, ...) and show the output."
[ -n "$STRUCTURAL" ] && [ -z "$MAP_UPDATED" ] && MISSING="${MISSING:+$MISSING
}- This session added or removed source files, so $MAP no longer describes the tree. Update it in the same change (see /project-domain). If the map genuinely needs no change, the user can reply 'skip dod'."
[ -z "$REVIEW_RAN" ] && MISSING="${MISSING:+$MISSING
}- Run a fresh-eyes review: /mr-fischoeder --diff scoped to the files below, or spawn a fresh-context review subagent scoped to them and to the shared bug checklist ($CHECKLIST), and fix real findings."

[ -z "$MISSING" ] && exit 0

# Name the files rather than saying "the session diff": the tree may hold another
# agent's in-flight work, and reviewing that as if it were yours is a false handoff.
TOUCHED="$(printf '%s\n%s\n' "$EDITED" "$BASH_EDITED" | grep -v '^[[:space:]]*$' | sort -u | sed 's/^/  /')"

jq -n --arg reason "$BLOCK_PREFIX but is missing:
$MISSING

Scope — the files THIS session changed, and only these:
$TOUCHED
Other agents may be working in the same tree; do not review or report on their changes.
Complete the missing steps, then finish. If the user explicitly wants to skip verification, they can reply 'skip dod'." \
  '{decision: "block", reason: $reason}'
