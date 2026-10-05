#!/usr/bin/env bash
#
# Install this AI config into Claude Code and Codex.
#
# It symlinks shared instructions and skills into both config directories, and
# installs Claude Code commands, agents, hooks, and statusline.
#
# Directory components are linked FILE BY FILE, so unrelated target entries survive.
#
# Usage:
#   ./install.sh                         # interactive: prompts for the Claude config dir
#   ./install.sh -c ~/.claudita          # target a custom Claude config dir (CLAUDE_CONFIG_DIR)
#   ./install.sh -c ~/.claude --no-codex # skip Codex
#   ./install.sh -c ~/.claudita -y       # non-interactive, use given/default dirs
#   ./install.sh --only skills           # install skills into enabled tools
#   ./install.sh --only skills --no-claude # install skills into Codex only
#   ./install.sh --only skills,commands  # install only skills + commands
#
# Flags:
#   -c, --config-dir DIR   Claude config dir (default: ~/.claude). Matches CLAUDE_CONFIG_DIR.
#       --codex-dir DIR    Codex config dir (default: ~/.codex).
#       --no-claude        Do not touch Claude Code.
#       --no-codex         Do not touch Codex.
#       --only LIST        Comma-separated components to install (default: all).
#                          Valid: instructions, commands, skills, agents, settings, codex.
#                          ('settings' wires Claude settings and Codex ledger hooks.)
#   -y, --yes              Assume defaults, do not prompt.
#   -h, --help             Show this help.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null || { echo "error: jq is required (brew install jq)" >&2; exit 1; }

ALL_COMPONENTS="instructions commands skills agents settings codex"

CLAUDE_DIR=""
CODEX_DIR="${HOME}/.codex"
DO_CODEX=1
DO_CLAUDE=1
ASSUME_YES=0
ONLY=""

usage() { sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --codex-dir)     CODEX_DIR="$2"; shift 2 ;;
    --no-claude)     DO_CLAUDE=0; shift ;;
    --no-codex)      DO_CODEX=0; shift ;;
    --only)          ONLY="$2"; shift 2 ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Validate --only against the known component list.
if [ -n "$ONLY" ]; then
  for c in ${ONLY//,/ }; do
    case " $ALL_COMPONENTS " in
      *" $c "*) ;;
      *) echo "error: unknown component '$c' (valid: $ALL_COMPONENTS)" >&2; exit 1 ;;
    esac
  done
fi

# True when component $1 was requested (everything is requested when --only is absent).
want() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# Shared components can target Codex without requiring a Claude config.
NEED_CLAUDE=0
if [ "$DO_CLAUDE" = 1 ]; then
  for c in instructions commands skills agents settings; do
    want "$c" && NEED_CLAUDE=1
  done
fi

NEED_CODEX=0
if [ "$DO_CODEX" = 1 ]; then
  for c in codex instructions skills settings; do
    want "$c" && NEED_CODEX=1
  done
fi

# Prompt for the Claude config dir when needed, not supplied, and not unattended.
if [ "$DO_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ] && [ -z "$CLAUDE_DIR" ]; then
  default_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  if [ "$ASSUME_YES" = 1 ]; then
    CLAUDE_DIR="$default_dir"
  else
    printf 'Claude config dir [%s]: ' "$default_dir"
    read -r answer
    CLAUDE_DIR="${answer:-$default_dir}"
  fi
fi

# Expand a leading ~ that survives when the value comes from a prompt.
CLAUDE_DIR="${CLAUDE_DIR/#\~/$HOME}"
CODEX_DIR="${CODEX_DIR/#\~/$HOME}"

stamp() { date +%Y%m%d%H%M%S; }

# Back up any different destination and link src -> dest.
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then return 0; fi
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    local bak="${dest}.bak.$(stamp)"
    mv "$dest" "$bak"
    echo "  backup  $dest -> $bak"
  fi
  ln -s "$src" "$dest"
  echo "  link    $dest -> $src"
}

# Link the CONTENTS of $src_dir into $dest_dir, one entry at a time, leaving any
# unrelated files already in $dest_dir untouched. Only same-named entries collide
# (and those are backed up by link()).
link_into_dir() {
  local src_dir="$1" dest_dir="$2"
  if [ -L "$dest_dir" ]; then
    local dest_target src_target
    dest_target="$(cd "$dest_dir" 2>/dev/null && pwd -P)" || dest_target=""
    src_target="$(cd "$src_dir" && pwd -P)"
    [ "$dest_target" = "$src_target" ] && return 0
    if [ -z "$dest_target" ]; then
      echo "  unlink  $dest_dir (was a dangling symlink)"
      rm "$dest_dir"
    fi
  fi
  mkdir -p "$dest_dir"
  local entry
  for entry in "$src_dir"/*; do
    [ -e "$entry" ] || continue   # nothing to link if the dir is empty
    link "$entry" "$dest_dir/$(basename "$entry")"
  done
}

# Merge statusLine + permissions.defaultMode + our hooks into the existing
# settings.json, PRESERVING every other key (model, theme, autoMode, ...). Creates a
# minimal file if none exists. settings.json is account-specific, so it is never
# symlinked or overwritten wholesale. The hook scripts live in this repo and are
# referenced by absolute path (like the statusline), so they are not symlinked.
# Requires jq. Note: defaultMode "auto" only takes effect in ~/.claude/settings.json;
# Claude Code ignores it in project/local settings.
#
# Hooks wired globally:
#   Stop         -> hooks/require_dod.sh                (report skipped Definition-of-Done steps)
#                -> shell/config_status.sh              (report uncommitted config changes)
#   SessionStart -> hooks/session_start_persona_pick.sh (pick a persona for the session)
#                -> hooks/session_start_domain_map.sh   (point at PROJECT_DOMAIN.md, or ask to bootstrap it)
#   PreToolUse   -> hooks/require_persona.sh            (deny source edits until a persona is invoked;
#                                                        on Edit|Write|MultiEdit and on Bash)
#                -> hooks/block_branch_creation.sh      (Bash: deny git branch creation — stay on main)
#                -> hooks/require_scoped_commit.sh      (Bash: note a commit that sweeps the shared index)
#                -> hooks/block_discard_changes.sh      (Bash: deny discarding another agent's uncommitted work)
#                -> hooks/session_ledger.sh pre          (record this session's changes, before/after each
#   PostToolUse  -> hooks/session_ledger.sh post          tool call, so it can commit exactly its own work)
#                -> hooks/block_kamal_mutations.sh      (Bash: deny Kamal prod-mutating commands)
#                -> hooks/require_domain_map.sh         (deny a source-tree sweep until /project-domain runs;
#                                                        on Grep|Glob and on Bash)
#   PostToolUse  -> hooks/ast_grep_scan.sh              (Edit|Write: structural lint of the written file)
merge_settings() {
  local dest="$1/settings.json"
  local base="{}"
  [ -f "$dest" ] && [ ! -L "$dest" ] && base="$(cat "$dest")"
  printf '%s' "$base" | jq \
    --arg sl "$REPO_DIR/shell/statusline.sh" \
    --arg status "$REPO_DIR/shell/config_status.sh" \
    --arg dod "$REPO_DIR/hooks/require_dod.sh" \
    --arg pick "$REPO_DIR/hooks/session_start_persona_pick.sh" \
    --arg domain "$REPO_DIR/hooks/session_start_domain_map.sh" \
    --arg persona "$REPO_DIR/hooks/require_persona.sh" \
    --arg no_branch "$REPO_DIR/hooks/block_branch_creation.sh" \
    --arg scoped_commit "$REPO_DIR/hooks/require_scoped_commit.sh" \
    --arg no_discard "$REPO_DIR/hooks/block_discard_changes.sh" \
    --arg no_kamal "$REPO_DIR/hooks/block_kamal_mutations.sh" \
    --arg domain_gate "$REPO_DIR/hooks/require_domain_map.sh" \
    --arg astgrep "$REPO_DIR/hooks/ast_grep_scan.sh" \
    --arg ledger "$REPO_DIR/hooks/session_ledger.sh" \
    '.statusLine = {type: "command", command: $sl}
     | .permissions.defaultMode = "auto"
     | .hooks.Stop = [ { hooks: [ { type: "command", command: $dod, statusMessage: "Checking Definition of Done..." }, { type: "command", command: $status } ] } ]
     | .hooks.SessionStart = [ { hooks: [ { type: "command", command: $pick, statusMessage: "Picking persona for this session..." }, { type: "command", command: $domain, statusMessage: "Locating the domain map..." } ] } ]
     | .hooks.PreToolUse = [
         { matcher: "Edit|Write|MultiEdit", hooks: [ { type: "command", command: $persona, statusMessage: "Checking persona..." } ] },
         { matcher: "Bash", hooks: [ { type: "command", command: $persona }, { type: "command", command: $no_branch }, { type: "command", command: $scoped_commit }, { type: "command", command: $no_discard }, { type: "command", command: $no_kamal }, { type: "command", command: $domain_gate } ] },
         { matcher: "Grep|Glob", hooks: [ { type: "command", command: $domain_gate, statusMessage: "Checking the domain map..." } ] },
         { matcher: "Bash|Edit|Write|NotebookEdit", hooks: [ { type: "command", command: ($ledger + " pre") } ] }
       ]
     | .hooks.PostToolUse = [
         { matcher: "Edit|Write", hooks: [ { type: "command", command: $astgrep, statusMessage: "Running ast-grep scan..." } ] },
         { matcher: "Bash|Edit|Write|NotebookEdit", hooks: [ { type: "command", command: ($ledger + " post") } ] }
       ]' \
    > "$dest.tmp" && mv "$dest.tmp" "$dest"
  echo "  merge   $dest (statusLine + Stop/SessionStart/PreToolUse/PostToolUse hooks; existing keys preserved)"
}

merge_codex_hooks() {
  local dest="$1/hooks.json" base="{}" tmp
  if [ -L "$dest" ]; then
    echo "error: refusing to replace symlinked Codex hooks file: $dest" >&2
    return 1
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    echo "error: Codex hooks path is not a regular file: $dest" >&2
    return 1
  fi
  [ -f "$dest" ] && base="$(cat "$dest")"
  tmp="$(mktemp "$1/.hooks.json.XXXXXX")" || { echo "error: could not create temporary Codex hooks file in $1" >&2; return 1; }
  printf '%s' "$base" | jq \
    --arg ledger "$REPO_DIR/hooks/session_ledger.sh" \
    'def without_command($command):
       map(.hooks = [.hooks[]? | select(.command != $command)] | select(.hooks | length > 0));
     .hooks = (.hooks // {})
     | .hooks.PreToolUse = ((.hooks.PreToolUse // [] | without_command("\"\($ledger)\" pre")) + [
         { matcher: "Bash|apply_patch", hooks: [{ type: "command", command: "\"\($ledger)\" pre" }] }
       ])
     | .hooks.PostToolUse = ((.hooks.PostToolUse // [] | without_command("\"\($ledger)\" post")) + [
         { matcher: "Bash|apply_patch", hooks: [{ type: "command", command: "\"\($ledger)\" post" }] }
       ])' \
    > "$tmp" || { rm -f "$tmp"; echo "error: could not merge Codex hooks into $dest" >&2; return 1; }
  mv "$tmp" "$dest" || { rm -f "$tmp"; echo "error: could not write Codex hooks to $dest" >&2; return 1; }
  echo "  merge   $dest (PreToolUse/PostToolUse session ledger hooks; existing hooks preserved)"
}

echo "Repo:        $REPO_DIR"
if [ "$DO_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ]; then echo "Claude dir:  $CLAUDE_DIR"; else echo "Claude:      skipped"; fi
if [ "$NEED_CODEX" = 1 ]; then echo "Codex dir:   $CODEX_DIR"; else echo "Codex:       skipped"; fi
[ -n "$ONLY" ] && echo "Only:        $ONLY"
echo

if [ "$DO_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ]; then
  echo "==> Claude Code"
  mkdir -p "$CLAUDE_DIR"
  if want instructions; then
    link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"   # one-liner: @AGENTS.md
    link "$REPO_DIR/AGENTS.md" "$CLAUDE_DIR/AGENTS.md"   # canonical instructions
  fi
  want commands && link_into_dir "$REPO_DIR/commands" "$CLAUDE_DIR/commands"
  want skills   && link_into_dir "$REPO_DIR/skills"   "$CLAUDE_DIR/skills"
  want agents   && link_into_dir "$REPO_DIR/agents"   "$CLAUDE_DIR/agents"
  want settings && merge_settings "$CLAUDE_DIR"
fi

if [ "$NEED_CODEX" = 1 ]; then
  echo
  echo "==> Codex"
  mkdir -p "$CODEX_DIR"
  if want instructions || want codex; then
    link "$REPO_DIR/AGENTS.md" "$CODEX_DIR/AGENTS.md"
  fi
  want skills && link_into_dir "$REPO_DIR/skills" "$CODEX_DIR/skills"
  echo "  note    Codex config.toml left untouched"
  if want settings; then
    merge_codex_hooks "$CODEX_DIR" || exit 1
    echo "  note    Session ledger hooks are merged into hooks.json"
  fi
fi

echo
echo "Done. Open a new session to pick up the changes."
