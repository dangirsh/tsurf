#!/usr/bin/env bash
# scripts/notify.sh -- Send ntfy notification from the server
# Usage: notify.sh <topic> <title> [message] [--priority <level>] [--tags <tags>]
#
# Examples:
#   notify.sh agents "Agent completed" "Task X finished successfully"
#   notify.sh backups "Backup failed" "restic snapshot failed" --priority high --tags warning
#   notify.sh agents "Agent completed" --priority low --tags white_check_mark

set -euo pipefail

NTFY_URL="http://localhost:2586"

TOPIC="${1:?Usage: notify.sh <topic> <title> [message] [--priority level] [--tags tags]}"
TITLE="${2:?Usage: notify.sh <topic> <title> [message] [--priority level] [--tags tags]}"
shift 2

MESSAGE=""
PRIORITY="default"
TAGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority)
      PRIORITY="$2"
      shift 2
      ;;
    --tags)
      TAGS="$2"
      shift 2
      ;;
    *)
      if [[ -z "$MESSAGE" ]]; then
        MESSAGE="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

CURL_ARGS=(
  --silent
  --show-error
  --max-time 10
  -H "Title: $TITLE"
  -H "Priority: $PRIORITY"
)

[[ -n "$TAGS" ]] && CURL_ARGS+=(-H "Tags: $TAGS")
[[ -n "$MESSAGE" ]] && CURL_ARGS+=(-d "$MESSAGE")

curl "${CURL_ARGS[@]}" "$NTFY_URL/$TOPIC"
