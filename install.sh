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
command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 1; }

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
  if [ -L "$dest" ] && [ ! -e "$dest" ]; then
    rm "$dest"   # a dangling link (e.g. from a moved checkout) has nothing to back up
    echo "  unlink  $dest (was a dangling symlink)"
  elif [ -L "$dest" ] || [ -e "$dest" ]; then
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
  # Entries removed from this repository leave dangling links behind.
  for entry in "$dest_dir"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      case "$(readlink "$entry")" in
        "$src_dir"/*) rm "$entry"; echo "  unlink  $entry (removed from repo)" ;;
      esac
    fi
  done
}

shell_quote() { jq -rn --arg value "$1" '$value | @sh'; }

# jq: the script path of a hook command written by this installer (any quoting).
HOOK_SCRIPT_JQ='def script: sub(" (pre|post|codex-pre|codex-start|codex-context)$"; "")
  | if startswith("\u0027") then .[1:-1] | gsub("\u0027\\\\\u0027\u0027"; "\u0027")
    elif startswith("\"") then .[1:-1] else . end;'

merge_hooks() {
  local dest="$1" host="$2" base="{}" tmp owned owned_paths dead commands path suffix script
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    echo "error: refusing non-regular or symlinked config: $dest" >&2
    return 1
  fi
  [ -f "$dest" ] && base="$(cat "$dest")"
  printf '%s' "$base" | jq empty 2>/dev/null || { echo "error: invalid hook config: $dest" >&2; return 1; }
  owned_paths="hooks/require_dod.sh shell/config_status.sh hooks/session_start_persona_pick.sh hooks/session_start_domain_map.sh hooks/require_persona.sh hooks/block_branch_creation.sh hooks/require_scoped_commit.sh hooks/block_discard_changes.sh hooks/block_kamal_mutations.sh hooks/require_domain_map.sh hooks/ast_grep_scan.sh hooks/session_ledger.sh"
  owned="$(for path in $owned_paths; do
    path="$REPO_DIR/$path"
    for suffix in "" " pre" " codex-pre" " codex-start" " codex-context" " post"; do
      printf '%s\n' "$path$suffix" "\"$path\"$suffix" "$(shell_quote "$path")$suffix"
    done
  done | jq -Rsc 'split("\n") | map(select(length > 0))')"
  # Scripts referenced by the config that no longer exist, e.g. after the checkout
  # moved. Owned hooks and statuslines pointing at them are replaced below.
  dead="$(printf '%s' "$base" | jq -r "$HOOK_SCRIPT_JQ"'[.hooks[]?[]?.hooks[]?.command, .statusLine.command?]
      | .[] | strings | script' | while IFS= read -r script; do
      [ -e "$script" ] || printf '%s\n' "$script"
    done | jq -Rsc 'split("\n") | map(select(length > 0))')"
  if [ "$host" = claude ]; then
    commands="$(jq -n \
      --arg domain "$(shell_quote "$REPO_DIR/hooks/session_start_domain_map.sh")" \
      --arg branch "$(shell_quote "$REPO_DIR/hooks/block_branch_creation.sh")" \
      --arg scoped "$(shell_quote "$REPO_DIR/hooks/require_scoped_commit.sh")" \
      --arg discard "$(shell_quote "$REPO_DIR/hooks/block_discard_changes.sh")" \
      --arg kamal "$(shell_quote "$REPO_DIR/hooks/block_kamal_mutations.sh")" \
      --arg lint "$(shell_quote "$REPO_DIR/hooks/ast_grep_scan.sh")" \
      --arg ledger "$(shell_quote "$REPO_DIR/hooks/session_ledger.sh")" \
      '{SessionStart:[{hooks:[{type:"command",command:$domain}]}],
        PreToolUse:[{matcher:"Bash",hooks:([$branch,$scoped,$discard,$kamal] | map({type:"command",command:.}))},
          {matcher:"Edit|Write",hooks:[{type:"command",command:($ledger + " pre")}]}],
        PostToolUse:[{matcher:"Edit|Write",hooks:[{type:"command",command:$lint}]},
          {matcher:"Edit|Write",hooks:[{type:"command",command:($ledger + " post")}]}]}')"
  else
    commands="$(jq -n --arg ledger "$(shell_quote "$REPO_DIR/hooks/session_ledger.sh")" \
      '{UserPromptSubmit:[{hooks:[{type:"command",command:($ledger + " codex-context")}]}],
        PreToolUse:[{matcher:"apply_patch",hooks:[{type:"command",command:($ledger + " codex-pre")}]}],
        PostToolUse:[{matcher:"apply_patch",hooks:[{type:"command",command:($ledger + " post")}]}]}')"
  fi
  tmp="$(mktemp "$(dirname "$dest")/.bots-burgers.XXXXXX")" || return 1
  printf '%s' "$base" | jq --argjson owned "$owned" --argjson additions "$commands" \
    --arg host "$host" --arg status "$(shell_quote "$REPO_DIR/shell/statusline.sh")" \
    --argjson dead "$dead" --arg rels "$owned_paths" "$HOOK_SCRIPT_JQ"'
    ($rels | split(" ") | map("/" + .)) as $rels
    | def moved($rel): script as $script | ($dead | index([$script])) and ($script | endswith($rel));
    (if $host == "claude" then .statusLine //= {type:"command",command:$status} else . end)
    | (if $host == "claude" and ((.statusLine.command // "") | moved("/shell/statusline.sh")) then .statusLine.command = $status else . end)
    | .hooks = ((.hooks // {}) | with_entries(.value |= map(
      .hooks |= map(select(.command as $command | ($owned | index([$command])) or ($command | any($rels[]; . as $rel | $command | moved($rel))) | not))
      | select(.hooks | length > 0))) | with_entries(select(.value | length > 0)))
    | reduce ($additions | keys[]) as $event (.; .hooks[$event] = ((.hooks[$event] // []) + $additions[$event]))
  ' > "$tmp" || { rm -f "$tmp"; echo "error: invalid hook config: $dest" >&2; return 1; }
  mv "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
  echo "  merge   $dest (owned hooks updated; unrelated settings preserved)"
}

banner() {
  cat <<'BANNER'
        _.-----------._
      .' .   .   .   . '.        B O T ' S   B U R G E R S
     /___________________\       agents, skills & hooks
     ~~~~~~~~~~~~~~~~~~~~~~      grand re-re-re-opening!
     [  [o]   ___   [o]  ]
     ~~~~~~~~~~~~~~~~~~~~~~
     \___________________/

BANNER
}

merge_settings() { merge_hooks "$1/settings.json" claude; }
merge_codex_hooks() { merge_hooks "$1/hooks.json" codex; }

banner
echo "Repo:        $REPO_DIR"
if [ "$DO_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ]; then echo "Claude dir:  $CLAUDE_DIR"; else echo "Claude:      skipped"; fi
if [ "$NEED_CODEX" = 1 ]; then echo "Codex dir:   $CODEX_DIR"; else echo "Codex:       skipped"; fi
[ -n "$ONLY" ] && echo "Only:        $ONLY"
echo

if [ "$DO_CLAUDE" = 1 ] && [ "$NEED_CLAUDE" = 1 ]; then
  echo "==> Claude Code"
  mkdir -p "$CLAUDE_DIR"
  if want instructions; then
    link "$REPO_DIR/instructions/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"   # one-liner: @AGENTS.md
    link "$REPO_DIR/instructions/AGENTS.md" "$CLAUDE_DIR/AGENTS.md"   # canonical instructions
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
    link "$REPO_DIR/instructions/AGENTS.md" "$CODEX_DIR/AGENTS.md"
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
