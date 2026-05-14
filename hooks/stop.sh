#!/bin/bash
# Claude Code Stop hook — fires when Claude finishes a response.
# Reads session name + last message from the transcript JSONL file.

CONFIG_FILE="$HOME/.claude/notifications.json"
ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)
[ "$ENABLED" = "false" ] && exit 0

SOUND_DONE=$(jq -r '.soundDone // "Ping"' "$CONFIG_FILE" 2>/dev/null)
SOUND_ERROR=$(jq -r '.soundError // "Basso"' "$CONFIG_FILE" 2>/dev/null)
SOUND_INTERRUPT=$(jq -r '.soundInterrupt // "Pop"' "$CONFIG_FILE" 2>/dev/null)
ACTION_FILE="/tmp/claude-current-action.json"
NOTIFIER="$HOME/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode"

resolve_sound() {
  local s="$1"
  if [[ "$s" == /* ]]; then
    echo "$s"
  else
    echo "/System/Library/Sounds/${s}.aiff"
  fi
}

input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
reason=$(echo "$input" | jq -r '.reason // empty')

# Small delay so the transcript is fully written before we read it
sleep 0.5

# Session name from ai-title event, cleaned up
session_name=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  raw=$(jq -r 'select(.type == "ai-title") | .aiTitle' "$transcript_path" 2>/dev/null | tail -1)
  if [ -n "$raw" ]; then
    session_name=$(echo "$raw" \
      | tr '-' ' ' \
      | python3 -c "import sys; print(sys.stdin.read().strip().title())" \
      | cut -c1-22 \
      | sed 's/ *$//')
  fi
fi

# Last message preview (markdown stripped, 60 chars)
last_msg=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  last_assistant=$(jq -c 'select(.type == "assistant")' "$transcript_path" 2>/dev/null | tail -1)
  if [ -n "$last_assistant" ]; then
    last_msg=$(echo "$last_assistant" \
      | jq -r '(.message.content // []) | map(select(.type == "text")) | .[0].text // ""' 2>/dev/null \
      | tr '\n' ' ' \
      | sed 's/\*\*//g; s/\*//g; s/#\+//g; s/`//g; s/[0-9]\+\. //g' \
      | tr -s ' ' \
      | sed 's/^ //; s/ $//' \
      | cut -c1-60)
  fi
fi

# Pick sound + title prefix based on stop reason, check per-event enabled flag
sound="$SOUND_DONE"
title_prefix="Claude Code"
event_enabled="true"
case "$reason" in
  *error*)
    sound="$SOUND_ERROR"
    title_prefix="⚠ Claude Code"
    event_enabled=$(jq -r '.enableError // true' "$CONFIG_FILE" 2>/dev/null)
    ;;
  *interrupt*|*cancel*)
    sound="$SOUND_INTERRUPT"
    title_prefix="⏸ Claude Code"
    event_enabled=$(jq -r '.enableInterrupt // true' "$CONFIG_FILE" 2>/dev/null)
    ;;
  *)
    event_enabled=$(jq -r '.enableDone // true' "$CONFIG_FILE" 2>/dev/null)
    ;;
esac
[ "$event_enabled" = "false" ] && exit 0

title="$title_prefix"
[ -n "$session_name" ] && title="$title_prefix — $session_name"

body="${last_msg:-Done.}"

sound_file=$(resolve_sound "$sound")
[ -f "$sound_file" ] && afplay "$sound_file" &

"$NOTIFIER" \
  --title "$title" \
  --subtitle "" \
  --message "$body"
