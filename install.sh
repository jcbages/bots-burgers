#!/usr/bin/env bash
#
# Install this AI config into Claude Code and (optionally) Codex.
#
# It symlinks the shared files (instructions, skills, commands, agents) into each
# tool's config directory and renders settings.json with the correct statusline path.
#
# Usage:
#   ./install.sh                         # interactive: prompts for the Claude config dir
#   ./install.sh -c ~/.claudita          # target a custom Claude config dir (CLAUDE_CONFIG_DIR)
#   ./install.sh -c ~/.claude --no-codex # skip Codex
#   ./install.sh -c ~/.claudita -y       # non-interactive, use given/default dirs
#
# Flags:
#   -c, --config-dir DIR   Claude config dir (default: ~/.claude). Matches CLAUDE_CONFIG_DIR.
#       --codex-dir DIR    Codex config dir (default: ~/.codex).
#       --no-codex         Do not touch Codex.
#   -y, --yes              Assume defaults, do not prompt.
#   -h, --help             Show this help.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_DIR=""
CODEX_DIR="${HOME}/.codex"
DO_CODEX=1
ASSUME_YES=0

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--config-dir) CLAUDE_DIR="$2"; shift 2 ;;
    --codex-dir)     CODEX_DIR="$2"; shift 2 ;;
    --no-codex)      DO_CODEX=0; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Prompt for the Claude config dir when not supplied and not running unattended.
if [ -z "$CLAUDE_DIR" ]; then
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

# Render settings.json (it embeds an absolute path, so it is generated, not linked).
render_settings() {
  local dest="$1/settings.json"
  local rendered
  rendered="$(sed \
    -e "s|__STATUSLINE__|$REPO_DIR/shell/statusline.sh|g" \
    -e "s|__SYNC__|$REPO_DIR/shell/sync.sh|g" \
    "$REPO_DIR/settings/settings.json")"
  if [ -e "$dest" ] && [ ! -L "$dest" ] && [ "$rendered" != "$(cat "$dest")" ]; then
    mv "$dest" "${dest}.bak.$(stamp)"
    echo "  backup  $dest -> ${dest}.bak.*"
  fi
  printf '%s\n' "$rendered" > "$dest"
  echo "  write   $dest"
}

echo "Repo:        $REPO_DIR"
echo "Claude dir:  $CLAUDE_DIR"
[ "$DO_CODEX" = 1 ] && echo "Codex dir:   $CODEX_DIR" || echo "Codex:       skipped"
echo

echo "==> Claude Code"
mkdir -p "$CLAUDE_DIR"
link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"   # one-liner: @AGENTS.md
link "$REPO_DIR/AGENTS.md" "$CLAUDE_DIR/AGENTS.md"   # canonical instructions
link "$REPO_DIR/commands"  "$CLAUDE_DIR/commands"
link "$REPO_DIR/skills"    "$CLAUDE_DIR/skills"
link "$REPO_DIR/agents"    "$CLAUDE_DIR/agents"
render_settings "$CLAUDE_DIR"

if [ "$DO_CODEX" = 1 ]; then
  echo
  echo "==> Codex (instructions only; skills/settings are Claude-specific)"
  mkdir -p "$CODEX_DIR"
  link "$REPO_DIR/AGENTS.md" "$CODEX_DIR/AGENTS.md"
  echo "  note    Codex config.toml left untouched; see codex/config.example.toml"
fi

echo
echo "Done. Open a new session to pick up the changes."
