#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
TOKENS_USED=$((TOTAL_IN + TOTAL_OUT))

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

if [ "$PCT" -ge 90 ]; then COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then COLOR="$YELLOW"
else COLOR="$GREEN"; fi

FILLED=$((PCT / 10))
EMPTY=$((10 - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%${EMPTY}s" | tr ' ' '░')

echo -e "[$MODEL] $BRANCH | ${TOKENS_USED} tokens | ${COLOR}${BAR} ${PCT}%${RESET}"
