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

mkdir -p "$W/claude-settings"
jq -n --arg old "$ROOT/hooks/require_persona.sh" '{permissions:{defaultMode:"default"},statusLine:{type:"command",command:"custom-status"},hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"custom-pre"},{type:"command",command:$old}]}],Stop:[{hooks:[{type:"command",command:"custom-stop"}]}]}}' > "$W/claude-settings/settings.json"
"$ROOT/install.sh" -y --only settings --no-codex -c "$W/claude-settings" >/dev/null
check "default" "$(jq -r '.permissions.defaultMode' "$W/claude-settings/settings.json")" "Claude preserves permission choice"
check "custom-status" "$(jq -r '.statusLine.command' "$W/claude-settings/settings.json")" "Claude preserves custom statusline"
check "custom-pre" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$W/claude-settings/settings.json")" "Claude preserves unrelated tool hooks"
check "custom-stop" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$W/claude-settings/settings.json")" "Claude preserves unrelated stop hooks"
check "0" "$(jq '[.hooks[][] | .hooks[] | select(.command | test("require_persona|require_domain_map|require_dod|config_status"))] | length' "$W/claude-settings/settings.json")" "Claude removes legacy ritual hooks"
check "1" "$(jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("session_start_persona_pick.sh"))] | length' "$W/claude-settings/settings.json")" "Claude installs the persona pick hook"
cp "$W/claude-settings/settings.json" "$W/claude-first.json"
"$ROOT/install.sh" -y --only settings --no-codex -c "$W/claude-settings" >/dev/null
check "0" "$(cmp -s "$W/claude-first.json" "$W/claude-settings/settings.json"; echo $?)" "Claude settings merge is idempotent"

old_repo="$W/old ' checkout"
live_repo="$W/live-other"
mkdir -p "$W/moved-settings" "$live_repo/hooks"
: > "$live_repo/hooks/session_ledger.sh"
jq -n --arg stale "$(jq -rn --arg p "$old_repo/hooks/session_ledger.sh" '$p | @sh') pre" \
  --arg stale_guard "\"$old_repo/hooks/block_branch_creation.sh\"" \
  --arg live "'$live_repo/hooks/session_ledger.sh' pre" \
  --arg status "$(jq -rn --arg p "$old_repo/shell/statusline.sh" '$p | @sh')" \
  '{statusLine:{type:"command",command:$status},hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$stale_guard},{type:"command",command:$live}]},{matcher:"Edit",hooks:[{type:"command",command:$stale}]}]}}' > "$W/moved-settings/settings.json"
"$ROOT/install.sh" -y --only settings --no-codex -c "$W/moved-settings" >/dev/null
check "0" "$(jq '[.hooks[][] | .hooks[] | select(.command | contains("old "))] | length' "$W/moved-settings/settings.json")" "hooks from a moved checkout are replaced"
check "1" "$(jq --arg live "$live_repo" '[.hooks[][] | .hooks[] | select(.command | contains($live))] | length' "$W/moved-settings/settings.json")" "same-named hooks with a live script are preserved"
check "1" "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command | endswith("block_branch_creation.sh'"'"'"))] | length' "$W/moved-settings/settings.json")" "moved checkout hooks are not duplicated"
check "'$ROOT/shell/statusline.sh'" "$(jq -r '.statusLine.command' "$W/moved-settings/settings.json")" "a statusline from a moved checkout is repointed"

mkdir -p "$W/claude-dangling/skills"
ln -s "$W/gone/skills/project-domain" "$W/claude-dangling/skills/project-domain"
"$ROOT/install.sh" -y --only skills --no-codex -c "$W/claude-dangling" >/dev/null
shopt -s nullglob
backups=("$W/claude-dangling/skills/project-domain".bak.*)
shopt -u nullglob
check "0" "${#backups[@]}" "dangling links are replaced without a backup"
check "$ROOT/skills/project-domain" "$(readlink "$W/claude-dangling/skills/project-domain")" "dangling links are repointed"

check "Edit|Write Edit|Write" "$(jq -r --arg ledger "$ROOT/hooks/session_ledger.sh" '[.hooks.PreToolUse[], .hooks.PostToolUse[] | select(any(.hooks[]; .command | contains($ledger))) | .matcher] | join(" ")' "$W/moved-settings/settings.json")" "Claude ledger hooks skip Bash calls"

fake_repo="$W/fake-repo"
mkdir -p "$fake_repo/skills/kept" "$W/claude-prune/skills"
cp "$ROOT/install.sh" "$fake_repo/install.sh"
ln -s "$fake_repo/skills/retired" "$W/claude-prune/skills/retired"
ln -s "$W/elsewhere/custom" "$W/claude-prune/skills/custom"
"$fake_repo/install.sh" -y --only skills --no-codex -c "$W/claude-prune" >/dev/null
check "0" "$([ -L "$W/claude-prune/skills/retired" ] && echo 1 || echo 0)" "links to skills removed from the repo are pruned"
check "1" "$([ -L "$W/claude-prune/skills/custom" ] && echo 1 || echo 0)" "dangling links owned by something else are kept"

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
jq --arg old "'$ROOT/hooks/session_ledger.sh' codex-start" '.hooks.SessionStart[0].hooks += [{type:"command",command:$old}]' "$W/codex-settings/hooks.json" > "$W/seed.json"
mv "$W/seed.json" "$W/codex-settings/hooks.json"
jq --arg old "\"$ROOT/hooks/session_ledger.sh\" pre" --arg current "\"$ROOT/hooks/session_ledger.sh\" codex-pre" '.hooks.PreToolUse += [{matcher:"Bash|apply_patch",hooks:[{type:"command",command:$old},{type:"command",command:$current}]}]' "$W/codex-settings/hooks.json" > "$W/seed.json"
mv "$W/seed.json" "$W/codex-settings/hooks.json"
printf 'leave this temp target alone\n' > "$W/hooks-temp-target"
ln -s "$W/hooks-temp-target" "$W/codex-settings/hooks.json.tmp"
"$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-settings" >/dev/null
check "keep this" "$(jq -r '.description' "$W/codex-settings/hooks.json")" "Codex hook merge preserves file metadata"
check "keep-this-hook" "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex hook merge preserves unrelated events"
check "0" "$(jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" codex-start"))] | length' "$W/codex-settings/hooks.json")" "Codex removes retired ledger session hooks"
check "'$ROOT/hooks/session_ledger.sh' codex-context" "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex supplies ledger context on user prompts"
check "apply_patch" "$(jq -r '.hooks.PreToolUse[-1].matcher' "$W/codex-settings/hooks.json")" "Codex ledger pre-hooks run only for patches"
check "apply_patch" "$(jq -r '.hooks.PostToolUse[-1].matcher' "$W/codex-settings/hooks.json")" "Codex ledger post-hooks run only for patches"
check "existing-pre-hook" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex hook merge preserves existing tool hooks"
check "'$ROOT/hooks/session_ledger.sh' codex-pre" "$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex installs its ledger pre-hook"
check "'$ROOT/hooks/session_ledger.sh' post" "$(jq -r '.hooks.PostToolUse[-1].hooks[0].command' "$W/codex-settings/hooks.json")" "Codex installs its ledger post-hook"
check "leave this temp target alone" "$(cat "$W/hooks-temp-target")" "Codex merge does not follow a predictable temp-file symlink"
check "1" "$([ -L "$W/codex-settings/hooks.json.tmp" ] && echo 1 || echo 0)" "Codex merge leaves unrelated temp-path symlinks intact"

"$ROOT/install.sh" -y --only settings --no-claude --codex-dir "$W/codex-settings" >/dev/null
check "1" "$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" codex-pre"))] | length' "$W/codex-settings/hooks.json")" "rerunning settings install does not duplicate Codex pre-hooks"
check "0" "$(jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" codex-start"))] | length' "$W/codex-settings/hooks.json")" "rerunning settings install keeps retired ledger hooks removed"
check "1" "$(jq '[.hooks.UserPromptSubmit[] | .hooks[] | select(.command | contains("session_ledger.sh") and endswith(" codex-context"))] | length' "$W/codex-settings/hooks.json")" "rerunning settings install does not duplicate Codex prompt hooks"
check "1" "$(jq '[.hooks.SessionStart[] | .hooks[] | select(.command | contains("session_start_persona_pick.sh"))] | length' "$W/codex-settings/hooks.json")" "Codex installs the persona pick hook once"
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

"$ROOT/install.sh" -y --only instructions -c "$W/claude-instructions" --codex-dir "$W/codex-instructions" >/dev/null
check "$ROOT/instructions/AGENTS.md" "$(readlink "$W/claude-instructions/AGENTS.md")" "Claude global instructions use the canonical global file"
check "$ROOT/instructions/CLAUDE.md" "$(readlink "$W/claude-instructions/CLAUDE.md")" "Claude global entry point uses the global include"
check "$ROOT/instructions/AGENTS.md" "$(readlink "$W/codex-instructions/AGENTS.md")" "Codex global instructions use the canonical global file"

mkdir -p "$W/claude-invalid"
printf '{invalid json\n' > "$W/claude-invalid/settings.json"
if "$ROOT/install.sh" -y --only settings --no-codex -c "$W/claude-invalid" >/dev/null 2>&1; then result=success; else result=failure; fi
check failure "$result" "invalid Claude settings stop installation"
check '{invalid json' "$(cat "$W/claude-invalid/settings.json")" "invalid Claude settings remain intact"
mkdir -p "$W/claude-linked"
printf '{}\n' > "$W/claude-target.json"
ln -s "$W/claude-target.json" "$W/claude-linked/settings.json"
if "$ROOT/install.sh" -y --only settings --no-codex -c "$W/claude-linked" >/dev/null 2>&1; then result=success; else result=failure; fi
check failure "$result" "Claude settings symlinks are refused"
check '{}' "$(cat "$W/claude-target.json")" "Claude settings symlink target remains intact"

quoted_repo="$W/repo ' with spaces"
mkdir -p "$quoted_repo"
cp "$ROOT/install.sh" "$quoted_repo/install.sh"
ln -s "$ROOT/hooks" "$quoted_repo/hooks"
"$quoted_repo/install.sh" -y --only settings --no-codex -c "$W/quoted-settings" >/dev/null
command="$(jq -r '.hooks.SessionStart[-1].hooks[0].command' "$W/quoted-settings/settings.json")"
if printf '{}' | bash -c "$command" >/dev/null 2>&1; then result=success; else result=failure; fi
check success "$result" "hook commands execute from a path containing spaces and an apostrophe"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
