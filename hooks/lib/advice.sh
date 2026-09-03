#!/usr/bin/env bash
#
# Optimistic gates (AGENTS.md): a gate names the hazard and lets the work through.
# PreToolUse advice also reaches the model, which can still change course; Stop
# advice must not, because feedback there resumes the very turn the user is ending.

advise_tool() { # <text>
  jq -n --arg t "$1" \
    '{systemMessage:$t, hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$t}}'
}

advise_user() { # <text>
  jq -n --arg t "$1" '{systemMessage:$t}'
}
