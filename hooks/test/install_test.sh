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

mkdir -p "$W/codex-settings"
cat > "$W/codex-settings/hooks.json" <<'JSON'
{
  "description": "keep this",
  "hooks": {
    "SessionStart": [{"matcher":"startup","hooks":[{"type":"command","command":"keep-this-hook"}]}],
    "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"existing-pre-hook"}]}]
  }
}
JSON
printf 'leave this temp target alone\n' > "$W/hooks-temp-target"
ln -s "$W/hooks-temp-target" "$W/codex-settings/hooks.json.tmp"
"$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-settings" >/dev/null
check "keep this" "$(jq -r '.description' "$W/codex-settings/hooks.json")" "Codex hook merge preserves file metadata"
check "keep-this-hook" "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex hook merge preserves unrelated events"
check "existing-pre-hook" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex hook merge preserves existing tool hooks"
check "\"$ROOT/hooks/session_ledger.sh\" pre" "$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex installs its ledger pre-hook"
check "\"$ROOT/hooks/session_ledger.sh\" post" "$(jq -r '.hooks.PostToolUse[-1].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex installs its ledger post-hook"
check "leave this temp target alone" "$(cat "$W/hooks-temp-target")" "Codex merge does not follow a predictable temp-file symlink"
check "1" "$([ -L "$W/codex-settings/hooks.json.tmp" ] && echo 1 || echo 0)" "Codex merge leaves unrelated temp-path symlinks intact"

"$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-settings" >/dev/null
check "1" "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" pre"))] | length' "$W/codex-settings/hooks.json")" "rerunning settings install does not duplicate Codex pre-hooks"
check "1" "$(jq '[.hooks.PostToolUse[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" post"))] | length' "$W/codex-settings/hooks.json")" "rerunning settings install does not duplicate Codex post-hooks"

mkdir -p "$W/codex-invalid"
printf '{invalid json\n' > "$W/codex-invalid/hooks.json"
if "$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-invalid" >/dev/null 2>&1; then
  invalid_install="succeeded"
else
  invalid_install="failed"
fi
check "failed" "$invalid_install" "invalid Codex hooks config stops the install"
check "{invalid json" "$(cat "$W/codex-invalid/hooks.json" | tr -d '\n')" "invalid Codex hooks config is left intact"

mkdir -p "$W/codex-linked-settings" "$W/external-codex-settings"
printf '{"hooks":{}}\n' > "$W/external-codex-settings/hooks.json"
ln -s "$W/external-codex-settings/hooks.json" "$W/codex-linked-settings/hooks.json"
if "$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-linked-settings" >/dev/null 2>&1; then
  linked_install="succeeded"
else
  linked_install="failed"
fi
check "failed" "$linked_install" "Codex install refuses a symlinked hooks config"
check '{"hooks":{}}' "$(cat "$W/external-codex-settings/hooks.json" | tr -d '\n')" "symlink target is left intact"

mkdir -p "$W/codex-directory-settings/hooks.json"
if "$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-directory-settings" >/dev/null 2>&1; then
  directory_install="succeeded"
else
  directory_install="failed"
fi
check "failed" "$directory_install" "Codex install rejects a directory at hooks.json"
check "1" "$([ -d "$W/codex-directory-settings/hooks.json" ] && echo 1 || echo 0)" "Codex config directory is left intact"

"$ROOT/install.sh" -y --only skills -c "$W/claude" --codex-dir "$W/codex" >/dev/null
shopt -s nullglob
backups=("$W/codex/skills/project-domain".bak.*)
shopt -u nullglob
check "0" "${#backups[@]}" "rerunning does not back up an unchanged skill link"

"$ROOT/install.sh" -y --only skills --no-codex -c "$W/claude-no-codex" --codex-dir "$W/no-codex" >/dev/null
check "0" "$([ -e "$W/no-codex" ] && echo 1 || echo 0)" "--no-codex leaves the Codex target untouched"

mkdir -p "$W/home"
codex_skill_install="$(HOME="$W/home" "$ROOT/install.sh" -y --only skills --no-claude --codex-dir "$W/codex-only")"
check "0" "$([ -e "$W/home/.claude" ] && echo 1 || echo 0)" "--no-claude does not create a Claude config"
check "$ROOT/skills/project-domain" "$(readlink "$W/codex-only/skills/project-domain")" "Codex-only install still links skills"
check "0" "$(printf '%s' "$codex_skill_install" | grep -c 'Session ledger hooks are merged' || true)" "skills-only install does not claim to merge hooks"

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
