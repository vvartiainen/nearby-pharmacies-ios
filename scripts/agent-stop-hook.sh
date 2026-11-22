#!/bin/bash
# Stop hook for Claude Code and Codex: check changed Swift files with swift-format.
#
# Both agents send a JSON object on stdin and treat exit code 2 as "keep working",
# using stderr as the reason. Exit 0 with no output lets the agent stop.
#
# When the agent is already continuing because of a Stop hook, report a
# persistent failure once without starting another continuation.

set -u

root=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
stop_hook_active=$(plutil -extract stop_hook_active raw -o - - 2>/dev/null) || stop_hook_active=false

if output=$("$root/scripts/style.sh" check 2>&1); then
  exit 0
fi

if [ "$stop_hook_active" = "true" ]; then
  printf '%s\n' '{"systemMessage":"Swift style check still fails after one retry. Run scripts/style.sh check in nearby-pharmacies-ios and fix the reported files."}'
  exit 0
fi

{
  echo 'Swift style check failed for changed files.'
  printf '%s\n' "$output" | head -n 80
  echo
  echo "Run scripts/style.sh format to fix formatting, fix any remaining rule by hand,"
  echo "then confirm with scripts/style.sh check before finishing."
} >&2
exit 2
