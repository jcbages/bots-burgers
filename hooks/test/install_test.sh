#!/usr/bin/env bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

passed=0; failed=0
check() {
  if [ "$1" = "$2" ]; then
    passed=$((passed+1)); printf '  ok   %s\n' "$3"
  else
    failed=$((failed+1)); printf '  FAIL %s — want %s, got %s\n' "$3" "$1" "$2"
  fi
}

mkdir -p "$W/codex/skills/.system"
printf 'preserve me\n' > "$W/codex/skills/.system/marker"

"$ROOT/install.sh" -y --only skills -c "$W/claude" --codex-dir "$W/codex" >/dev/null
check "$ROOT/skills/project-domain" "$(readlink "$W/codex/skills/project-domain")" "Codex gets the project-domain skill"
check "preserve me" "$(cat "$W/codex/skills/.system/marker")" "existing unrelated Codex skills remain"
check "$ROOT/skills/project-domain" "$(readlink "$W/claude/skills/project-domain")" "Claude still gets the project-domain skill"

"$ROOT/install.sh" -y --only skills -c "$W/claude" --codex-dir "$W/codex" >/dev/null
shopt -s nullglob
backups=("$W/codex/skills/project-domain".bak.*)
shopt -u nullglob
check "0" "${#backups[@]}" "rerunning does not back up an unchanged skill link"

"$ROOT/install.sh" -y --only skills --no-codex -c "$W/claude-no-codex" --codex-dir "$W/no-codex" >/dev/null
check "0" "$([ -e "$W/no-codex" ] && echo 1 || echo 0)" "--no-codex leaves the Codex target untouched"

mkdir -p "$W/home"
HOME="$W/home" "$ROOT/install.sh" -y --only skills --no-claude --codex-dir "$W/codex-only" >/dev/null
check "0" "$([ -e "$W/home/.claude" ] && echo 1 || echo 0)" "--no-claude does not create a Claude config"
check "$ROOT/skills/project-domain" "$(readlink "$W/codex-only/skills/project-domain")" "Codex-only install still links skills"

mkdir -p "$W/codex-linked" "$W/shared-skills/.system"
printf 'keep linked skills\n' > "$W/shared-skills/.system/marker"
ln -s "$W/shared-skills" "$W/codex-linked/skills"
"$ROOT/install.sh" -y --only skills --no-claude --codex-dir "$W/codex-linked" >/dev/null
check "$W/shared-skills" "$(readlink "$W/codex-linked/skills")" "existing Codex skill directory symlinks stay connected"
check "keep linked skills" "$(cat "$W/shared-skills/.system/marker")" "pre-existing skills in a linked directory survive"
check "$ROOT/skills/project-domain" "$(readlink "$W/shared-skills/project-domain")" "new skills join the existing linked directory"

mkdir -p "$W/codex-self"
ln -s "$ROOT/skills" "$W/codex-self/skills"
"$ROOT/install.sh" -y --only skills --no-claude --codex-dir "$W/codex-self" >/dev/null
check "$ROOT/skills" "$(readlink "$W/codex-self/skills")" "a directory already linked to the source is left intact"

mkdir -p "$W/codex-collision/skills" "$W/custom-project-domain"
printf 'keep the custom skill\n' > "$W/custom-project-domain/marker"
ln -s "$W/custom-project-domain" "$W/codex-collision/skills/project-domain"
"$ROOT/install.sh" -y --only skills --no-claude --codex-dir "$W/codex-collision" >/dev/null
shopt -s nullglob
backups=("$W/codex-collision/skills/project-domain".bak.*)
shopt -u nullglob
backup_target=""
[ "${#backups[@]}" -gt 0 ] && backup_target="$(readlink "${backups[0]}")"
check "1" "${#backups[@]}" "a conflicting skill symlink gets a backup"
check "$W/custom-project-domain" "$backup_target" "the backup retains the custom skill target"
check "$ROOT/skills/project-domain" "$(readlink "$W/codex-collision/skills/project-domain")" "the configured skill takes precedence after backup"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
