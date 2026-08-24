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

MISSING=""
[ -z "$TESTS_RAN" ] && MISSING="- Run the touched tests (the stack's test runner — bin/ci, rails test, rspec, npm test, pytest, go test, flutter test, ...) and show the output."
[ -z "$REVIEW_RAN" ] && MISSING="${MISSING:+$MISSING
}- Run a fresh-eyes review: /mr-fischoeder --diff on the session diff (it reviews the working tree, committed and uncommitted — not just PRs), or spawn a fresh-context review subagent scoped to the shared bug checklist ($CHECKLIST), and fix real findings."

[ -z "$MISSING" ] && exit 0

jq -n --arg reason "Definition of Done gate (AGENTS.md): this session edited product code but is missing:
$MISSING
Complete the missing steps, then finish. If the user explicitly wants to skip verification, they can reply 'skip dod'." \
  '{decision: "block", reason: $reason}'
