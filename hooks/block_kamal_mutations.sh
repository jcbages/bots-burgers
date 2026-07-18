#!/usr/bin/env bash
#
# PreToolUse hook (Bash): deny Kamal lifecycle / prod-mutating commands (deploy,
# rollback, remove, prune, app boot/stop, server exec, ...). Shipping and prod
# mutations are a human decision. Only matches `kamal ...`, so it's inert in projects
# that don't use Kamal. Wired globally by install.sh (see merge_settings).
#
set -u

CMD="$(jq -r '.tool_input.command // empty')"

if printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|[|;&(])(bin/)?kamal[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(deploy|redeploy|rollback|remove|prune|setup|upgrade|app[[:space:]]+(boot|start|stop|remove|stale_containers)|accessory[[:space:]]+(boot|start|stop|restart|remove|upgrade)|proxy[[:space:]]+(boot|start|stop|restart|remove|reboot|boot_config)|server[[:space:]]+(bootstrap|exec|reboot))([[:space:]]|$)'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Prod-safety rule: the agent never runs Kamal lifecycle or mutating commands (deploy, rollback, remove, prune, app boot/stop, server exec, ...). Shipping and prod mutations are a human decision — ask the user to run the exact command themselves with the ! prefix."}}
JSON
fi
