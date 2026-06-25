#!/usr/bin/env bash
# Cursor afterAgentResponse hook — primary "done" notification trigger.

NOTIF_PROFILE="cursor"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
ACTION_FILE="/tmp/cursor-current-action.json"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/tmp/cursor-notif-hook.log"

if [ -f "$HOME/.cursor/hooks/read-config.sh" ]; then
  source "$HOME/.cursor/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

input=$(cat)
echo "$input" > /tmp/cursor-agent-response-debug.json 2>/dev/null
finish_long_timers "cursor"

[ -x "$NOTIFIER" ] || exit 0
cfg_should_notify || exit 0
[ "$(cfg_val enableDone true)" != "false" ] || exit 0
cfg_in_quiet_hours && exit 0

TITLE_PREFIX="$(cfg_val titlePrefix "Cursor")"
[ -z "$TITLE_PREFIX" ] && TITLE_PREFIX="Cursor"
SOUND="$(cfg_val soundDone "Purr")"
VOL="$(cfg_val volumeDone "1.0")"
PREVIEW="$(cfg_val previewLength "sentence")"

raw_text=$(echo "$input" | jq -r '.text // empty' 2>/dev/null)
if [ -n "$raw_text" ] && [ "$raw_text" != "null" ]; then
  raw_text=$(echo "$raw_text" \
    | sed 's/\*\*//g; s/\*//g; s/^#\+[[:space:]]//g; s/`//g' \
    | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//')
fi

body=""
if [ -n "$raw_text" ]; then
  body=$(preview_body "$raw_text" "$PREVIEW")
fi
[ -z "$body" ] && body="Done."

subtitle=""
workspace=$(echo "$input" | jq -r '.workspace_roots[0] // empty' 2>/dev/null)
if [ -n "$workspace" ] && [ "$workspace" != "null" ]; then
  subtitle=$(basename "$workspace")
fi

elapsed_str=""
if [ -f "$ACTION_FILE" ]; then
  last_ts=$(jq -r '.ts // 0' "$ACTION_FILE" 2>/dev/null)
  now=$(date +%s)
  if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
    elapsed=$(( now - last_ts ))
    if [ "$elapsed" -gt 60 ]; then
      elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
    elif [ "$elapsed" -gt 0 ]; then
      elapsed_str="${elapsed}s"
    fi
  fi
fi

if [ -n "$elapsed_str" ]; then
  if [ -n "$subtitle" ]; then
    subtitle="$subtitle · $elapsed_str"
  else
    subtitle="$elapsed_str"
  fi
fi

echo "[$(date)] firing cursor notifier: title=$TITLE_PREFIX subtitle=$subtitle body=${body:0:50}" >> "$LOG"
notify_queue "/tmp/noto-cursor-pending.json" "cursor" "Cursor" \
  "$TITLE_PREFIX" "$subtitle" "$body" "$SOUND" "$VOL" "done"
exit 0
