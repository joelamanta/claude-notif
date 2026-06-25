#!/usr/bin/env bash
# Claude Code Stop hook

NOTIF_PROFILE="claude"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/read-config.sh
if [ -f "$HOME/.claude/hooks/noto-read-config.sh" ]; then
  source "$HOME/.claude/hooks/noto-read-config.sh"
else
  source "$HOOK_DIR/lib/read-config.sh"
fi

ACTION_FILE="/tmp/claude-current-action.json"
input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
reason=$(echo "$input" | jq -r '.reason // empty')
session_id_stop=$(echo "$input" | jq -r '.session_id // empty')

finish_long_timers "claude"

[ -x "$NOTIFIER" ] || exit 0
cfg_should_notify || exit 0
cfg_in_quiet_hours && exit 0

sleep 0.5

session_name=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  raw=$(jq -r 'select(.type == "ai-title") | .aiTitle' "$transcript_path" 2>/dev/null | tail -1)
  if [ -n "$raw" ]; then
    session_name=$(echo "$raw" \
      | tr '-' ' ' \
      | python3 -c "import sys; print(sys.stdin.read().strip().title())" \
      | cut -c1-22 | sed 's/ *$//')
  fi
fi

PREVIEW="$(cfg_val previewLength "sentence")"
last_msg=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  last_assistant=$(jq -c 'select(.type == "assistant")' "$transcript_path" 2>/dev/null | tail -1)
  if [ -n "$last_assistant" ]; then
    raw_text=$(echo "$last_assistant" \
      | jq -r '(.message.content // []) | map(select(.type == "text")) | .[0].text // ""' 2>/dev/null \
      | tr '\n' ' ' \
      | sed 's/\*\*//g; s/\*//g; s/#\+//g; s/`//g; s/[0-9]\+\. //g' \
      | tr -s ' ' | sed 's/^ //; s/ $//')
    if [ -n "$raw_text" ]; then
      last_msg=$(preview_body "$raw_text" "$PREVIEW")
    fi
  fi
fi

elapsed_str=""
if [ -f "$ACTION_FILE" ]; then
  last_ts=$(jq -r '.ts // 0' "$ACTION_FILE" 2>/dev/null)
  now=$(date +%s)
  if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
    elapsed=$(( now - last_ts ))
    if [ "$elapsed" -gt 60 ]; then elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
    elif [ "$elapsed" -gt 0 ]; then elapsed_str="${elapsed}s"; fi
  fi
fi

TITLE_PREFIX="$(cfg_val titlePrefix "Claude Code")"
[ -z "$TITLE_PREFIX" ] && TITLE_PREFIX="Claude Code"
sound="$(cfg_val soundDone "Ping")"
vol="$(cfg_val volumeDone "1.0")"
title_prefix="$TITLE_PREFIX"

case "$reason" in
  *error*)
    [ "$(cfg_val enableError true)" = "false" ] && exit 0
    sound="$(cfg_val soundError "Basso")"
    vol="$(cfg_val volumeError "1.0")"
    title_prefix="⚠ $TITLE_PREFIX"
    ;;
  *interrupt*|*cancel*)
    [ "$(cfg_val enableInterrupt true)" = "false" ] && exit 0
    sound="$(cfg_val soundInterrupt "Pop")"
    vol="$(cfg_val volumeInterrupt "1.0")"
    title_prefix="⏸ $TITLE_PREFIX"
    ;;
  *)
    [ "$(cfg_val enableDone true)" = "false" ] && exit 0
    ;;
esac

title="$title_prefix"
[ -n "$session_name" ] && title="$title_prefix — $session_name"
body="${last_msg:-Done.}"

kind="done"
case "$reason" in
  *error*|*interrupt*|*cancel*) kind="alert" ;;
esac

notify_queue "/tmp/noto-claude-pending.json" "claude" "Claude" \
  "$title" "$elapsed_str" "$body" "$sound" "$vol" "$kind"

exit 0
