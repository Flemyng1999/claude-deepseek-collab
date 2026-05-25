#!/usr/bin/env bash
# Print a cold-start hint when the prompt looks suitable for DS delegation.
# This hook never runs DS and never modifies files.
set -euo pipefail

prompt=$(cat)

if [[ "$prompt" =~ [Dd]eep[Ss]eek ]] ||
   [[ "$prompt" =~ (^|[^[:alnum:]_])[Dd][Ss]([^[:alnum:]_]|$) ]] ||
   [[ "$prompt" =~ [Dd]elegate ]] ||
   [[ "$prompt" =~ [Bb]atch ]] ||
   [[ "$prompt" =~ [Pp]arallel ]] ||
   [[ "$prompt" =~ [Cc]heap[[:space:]]+[Mm]odel ]] ||
   [[ "$prompt" =~ [Rr]outer ]] ||
   [[ "$prompt" == *"路由"* ]] ||
   [[ "$prompt" == *"批量"* ]] ||
   [[ "$prompt" == *"初稿"* ]] ||
   [[ "$prompt" == *"草稿"* ]] ||
   [[ "$prompt" == *"多版本"* ]] ||
   [[ "$prompt" == *"低成本"* ]]; then
  echo "Hint: consider DS delegation with /ds for token-heavy draft work; Claude must audit before final output."
fi
