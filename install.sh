#!/usr/bin/env bash
#
# Install this AI config into Claude Code and (optionally) Codex.
#
# It symlinks the shared files (instructions, skills, commands, agents) into each
# tool's config directory and renders settings.json with the correct statusline path.
#
# Directory components (skills, commands, agents) are linked FILE BY FILE, so any
# skills/commands you already have in the target dir are left untouched.
#
# Usage:
#   ./install.sh                         # interactive: prompts for the Claude config dir
#   ./install.sh -c ~/.claudita          # target a custom Claude config dir (CLAUDE_CONFIG_DIR)
#   ./install.sh -c ~/.claude --no-codex # skip Codex
#   ./install.sh -c ~/.claudita -y       # non-interactive, use given/default dirs
#   ./install.sh --only skills           # install only the skills
#   ./install.sh --only skills,commands  # install only skills + commands
#
# Flags:
#   -c, --config-dir DIR   Claude config dir (default: ~/.claude). Matches CLAUDE_CONFIG_DIR.
#       --codex-dir DIR    Codex config dir (default: ~/.codex).
#       --no-codex         Do not touch Codex.
#       --only LIST        Comma-separated components to install (default: all).
#                          Valid: instructions, commands, skills, agents, settings, codex.
#                          ('settings' also wires the statusline + Stop/SessionStart/PreToolUse/PostToolUse hooks.)
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
ASSUME_YES=0
ONLY=""

usage() { sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --codex-dir)     CODEX_DIR="$2"; shift 2 ;;
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

# Do we need the Claude config dir at all? (codex is the only non-Claude component.)
NEED_CLAUDE=0
for c in instructions commands skills agents settings; do
  want "$c" && NEED_CLAUDE=1
done

# Prompt for the Claude config dir when needed, not supplied, and not unattended.
if [ "$NEED_CLAUDE" = 1 ] && [ -z "$CLAUDE_DIR" ]; then
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

# Back up whatever is at $dest (unless it is already a symlink) and link src -> dest.
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ]; then
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
  # An older install may have symlinked the whole dir; drop that so we link into a
  # real directory rather than into the repo itself.
  if [ -L "$dest_dir" ]; then
    echo "  unlink  $dest_dir (was a whole-dir symlink)"
    rm "$dest_dir"
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
#   Stop         -> hooks/require_dod.sh                (Definition-of-Done gate after source edits)
#                -> shell/sync.sh                       (auto-commit config changes)
#   SessionStart -> hooks/session_start_persona_pick.sh (pick a persona for the session)
#                -> hooks/session_start_domain_map.sh   (point at PROJECT_DOMAIN.md, or ask to bootstrap it)
#   PreToolUse   -> hooks/require_persona.sh            (deny edits until a persona is invoked)
#                -> hooks/block_branch_creation.sh      (Bash: deny git branch creation — stay on main)
#                -> hooks/block_kamal_mutations.sh      (Bash: deny Kamal prod-mutating commands)
#   PostToolUse  -> hooks/ast_grep_scan.sh              (Edit|Write: structural lint of the written file)
merge_settings() {
  local dest="$1/settings.json"
  local base="{}"
  [ -f "$dest" ] && [ ! -L "$dest" ] && base="$(cat "$dest")"
  printf '%s' "$base" | jq \
    --arg sl "$REPO_DIR/shell/statusline.sh" \
    --arg sync "$REPO_DIR/shell/sync.sh" \
    --arg dod "$REPO_DIR/hooks/require_dod.sh" \
    --arg pick "$REPO_DIR/hooks/session_start_persona_pick.sh" \
    --arg domain "$REPO_DIR/hooks/session_start_domain_map.sh" \
    --arg persona "$REPO_DIR/hooks/require_persona.sh" \
    --arg no_branch "$REPO_DIR/hooks/block_branch_creation.sh" \
    --arg no_kamal "$REPO_DIR/hooks/block_kamal_mutations.sh" \
    --arg astgrep "$REPO_DIR/hooks/ast_grep_scan.sh" \
    '.statusLine = {type: "command", command: $sl}
     | .permissions.defaultMode = "auto"
     | .hooks.Stop = [ { hooks: [ { type: "command", command: $dod, statusMessage: "Checking Definition of Done..." }, { type: "command", command: $sync } ] } ]
     | .hooks.SessionStart = [ { hooks: [ { type: "command", command: $pick, statusMessage: "Picking persona for this session..." }, { type: "command", command: $domain, statusMessage: "Locating the domain map..." } ] } ]
     | .hooks.PreToolUse = [
         { matcher: "Edit|Write|MultiEdit", hooks: [ { type: "command", command: $persona, statusMessage: "Checking persona..." } ] },
         { matcher: "Bash", hooks: [ { type: "command", command: $no_branch }, { type: "command", command: $no_kamal } ] }
       ]
     | .hooks.PostToolUse = [ { matcher: "Edit|Write", hooks: [ { type: "command", command: $astgrep, statusMessage: "Running ast-grep scan..." } ] } ]' \
    > "$dest.tmp" && mv "$dest.tmp" "$dest"
  echo "  merge   $dest (statusLine + Stop/SessionStart/PreToolUse/PostToolUse hooks; existing keys preserved)"
}

echo "Repo:        $REPO_DIR"
[ "$NEED_CLAUDE" = 1 ] && echo "Claude dir:  $CLAUDE_DIR"
if [ "$DO_CODEX" = 1 ] && want codex; then echo "Codex dir:   $CODEX_DIR"; else echo "Codex:       skipped"; fi
[ -n "$ONLY" ] && echo "Only:        $ONLY"
echo

if [ "$NEED_CLAUDE" = 1 ]; then
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

if [ "$DO_CODEX" = 1 ] && want codex; then
  echo
  echo "==> Codex (instructions only; skills/settings are Claude-specific)"
  mkdir -p "$CODEX_DIR"
  link "$REPO_DIR/AGENTS.md" "$CODEX_DIR/AGENTS.md"
  echo "  note    Codex config.toml left untouched; see codex/config.example.toml"
fi

echo
echo "Done. Open a new session to pick up the changes."
