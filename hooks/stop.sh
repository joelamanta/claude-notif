#!/bin/bash
# Claude Code — Stop hook

CONFIG_FILE="$HOME/.claude/notifications.json"
ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)
[ "$ENABLED" = "false" ] && exit 0

SOUND_DONE=$(jq -r '.soundDone // "Ping"' "$CONFIG_FILE" 2>/dev/null)
SOUND_ERROR=$(jq -r '.soundError // "Basso"' "$CONFIG_FILE" 2>/dev/null)
SOUND_INTERRUPT=$(jq -r '.soundInterrupt // "Pop"' "$CONFIG_FILE" 2>/dev/null)
VOL_DONE=$(jq -r '.volumeDone // 1.0' "$CONFIG_FILE" 2>/dev/null)
VOL_ERROR=$(jq -r '.volumeError // 1.0' "$CONFIG_FILE" 2>/dev/null)
VOL_INTERRUPT=$(jq -r '.volumeInterrupt // 1.0' "$CONFIG_FILE" 2>/dev/null)
TITLE_PREFIX=$(jq -r '.titlePrefix // "Claude Code"' "$CONFIG_FILE" 2>/dev/null)
[ -z "$TITLE_PREFIX" ] && TITLE_PREFIX="Claude Code"
PREVIEW=$(jq -r '.previewLength // "sentence"' "$CONFIG_FILE" 2>/dev/null)

# Quiet hours check
QUIET_ENABLED=$(jq -r '.quietEnabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$QUIET_ENABLED" = "true" ]; then
  QUIET_FROM=$(jq -r '.quietFrom // "22:00"' "$CONFIG_FILE" 2>/dev/null)
  QUIET_TO=$(jq -r '.quietTo // "08:00"' "$CONFIG_FILE" 2>/dev/null)
  now_m=$((10#$(date +%H) * 60 + 10#$(date +%M)))
  from_m=$((10#${QUIET_FROM%%:*} * 60 + 10#${QUIET_FROM##*:}))
  to_m=$((10#${QUIET_TO%%:*} * 60 + 10#${QUIET_TO##*:}))
  if [ "$from_m" -le "$to_m" ]; then
    [ "$now_m" -ge "$from_m" ] && [ "$now_m" -lt "$to_m" ] && exit 0
  else
    { [ "$now_m" -ge "$from_m" ] || [ "$now_m" -lt "$to_m" ]; } && exit 0
  fi
fi

ACTION_FILE="/tmp/claude-current-action.json"
NOTIFIER="/Users/teevoteam/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode"

resolve_sound() {
  local s="$1"
  [[ "$s" == /* ]] && echo "$s" || echo "/System/Library/Sounds/${s}.aiff"
}

# --- Parse stdin ---
input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
reason=$(echo "$input" | jq -r '.reason // empty')

# --- Cancel all long-running timers for this session ---
session_id_stop=$(echo "$input" | jq -r '.session_id // empty')
if [ -n "$session_id_stop" ]; then
  for pid_file in /tmp/claude-longtimer-${session_id_stop}-*.pid; do
    [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null && rm -f "$pid_file"
  done
  # legacy single-timer cleanup
  [ -f "/tmp/claude-longtimer-${session_id_stop}.pid" ] && \
    kill "$(cat "/tmp/claude-longtimer-${session_id_stop}.pid")" 2>/dev/null && \
    rm -f "/tmp/claude-longtimer-${session_id_stop}.pid"
fi

sleep 0.5

# --- Session name ---
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

# --- Last message preview ---
last_msg=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  last_assistant=$(jq -c 'select(.type == "assistant")' "$transcript_path" 2>/dev/null | tail -1)
  if [ -n "$last_assistant" ]; then
    raw_text=$(echo "$last_assistant" \
      | jq -r '(.message.content // []) | map(select(.type == "text")) | .[0].text // ""' 2>/dev/null \
      | tr '\n' ' ' \
      | sed 's/\*\*//g; s/\*//g; s/#\+//g; s/`//g; s/[0-9]\+\. //g' \
      | tr -s ' ' \
      | sed 's/^ //; s/ $//')

    case "$PREVIEW" in
      two)
        last_msg=$(echo "$raw_text" | python3 -c "
import sys, re
t = sys.stdin.read().strip()
m = re.search(r'^.*?[.!?]\s+.*?[.!?]', t)
print((m.group(0) if m else re.search(r'^.*?[.!?]', t).group(0) if re.search(r'^.*?[.!?]', t) else t[:160]))" 2>/dev/null)
        [ -z "$last_msg" ] && last_msg=$(echo "$raw_text" | sed 's/\([.!?]\).*/\1/')
        ;;
      full)
        last_msg=$(echo "$raw_text" | cut -c1-200)
        ;;
      *)
        last_msg=$(echo "$raw_text" | sed 's/\([.!?]\).*/\1/' | cut -c1-80)
        ;;
    esac
  fi
fi

# --- Elapsed time ---
elapsed_str=""
if [ -f "$ACTION_FILE" ]; then
  last_ts=$(jq -r '.ts // 0' "$ACTION_FILE" 2>/dev/null)
  now=$(date +%s)
  if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
    elapsed=$(( now - last_ts ))
    if [ "$elapsed" -gt 60 ]; then
      elapsed_str="$((elapsed / 60))m $((elapsed % 60))s"
    else
      elapsed_str="${elapsed}s"
    fi
  fi
fi

# --- Pick sound + title prefix based on stop reason ---
sound="$SOUND_DONE"
vol="$VOL_DONE"
case "$reason" in
  *error*)
    sound="$SOUND_ERROR"
    vol="$VOL_ERROR"
    title_prefix="⚠ $TITLE_PREFIX"
    ;;
  *interrupt*|*cancel*)
    sound="$SOUND_INTERRUPT"
    vol="$VOL_INTERRUPT"
    title_prefix="⏸ $TITLE_PREFIX"
    ;;
  *)
    title_prefix="$TITLE_PREFIX"
    ;;
esac

# --- Compose fields ---
title="$title_prefix"
[ -n "$session_name" ] && title="$title_prefix — $session_name"

subtitle="$elapsed_str"
body="${last_msg:-Done.}"

# --- Play sound ---
sound_file=$(resolve_sound "$sound")
[ -f "$sound_file" ] && afplay -v "$vol" "$sound_file" &

# --- Fire notification ---
"$NOTIFIER" \
  --title "$title" \
  --subtitle "$subtitle" \
  --message "$body"
