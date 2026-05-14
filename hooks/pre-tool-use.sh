#!/usr/bin/env bash
# Claude Code PreToolUse hook
# Writes current tool action to /tmp/claude-current-action.json
# If the tool is TodoWrite, also writes todo state to /tmp/claude-todos.json
# Fires approval notification for Bash commands (debounced 10s)

ACTION_FILE="/tmp/claude-current-action.json"
TODOS_FILE="/tmp/claude-todos.json"
APPROVAL_LOCK="/tmp/claude-notif-approval.lock"
CONFIG_FILE="$HOME/.claude/notifications.json"
NOTIFIER="$HOME/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode"

# Read hook input from stdin
input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -c '.tool_input // {}')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# --- Build a human-readable action label ---
action_label=""
case "$tool_name" in
  Read)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    base=$(basename "$file_path")
    action_label="Reading $base"
    ;;
  Edit|MultiEdit)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    base=$(basename "$file_path")
    action_label="Editing $base"
    ;;
  Write)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    base=$(basename "$file_path")
    action_label="Writing $base"
    ;;
  Bash)
    cmd=$(echo "$tool_input" | jq -r '.command // empty')
    # Truncate to first ~40 chars, strip newlines
    short_cmd=$(echo "$cmd" | head -1 | cut -c1-40)
    action_label="Bash: $short_cmd"

    # Approval notification — debounced 10s
    ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    APPROVAL_ENABLED=$(jq -r '.enableApproval // true' "$CONFIG_FILE" 2>/dev/null)
    if [ "$ENABLED" != "false" ] && [ "$APPROVAL_ENABLED" != "false" ] && [ -x "$NOTIFIER" ]; then
      # Quiet hours check
      QUIET_ENABLED=$(jq -r '.quietEnabled // false' "$CONFIG_FILE" 2>/dev/null)
      in_quiet=false
      if [ "$QUIET_ENABLED" = "true" ]; then
        QUIET_FROM=$(jq -r '.quietFrom // "22:00"' "$CONFIG_FILE" 2>/dev/null)
        QUIET_TO=$(jq -r '.quietTo // "08:00"' "$CONFIG_FILE" 2>/dev/null)
        now_m=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        from_m=$((10#${QUIET_FROM%%:*} * 60 + 10#${QUIET_FROM##*:}))
        to_m=$((10#${QUIET_TO%%:*} * 60 + 10#${QUIET_TO##*:}))
        if [ "$from_m" -le "$to_m" ]; then
          [ "$now_m" -ge "$from_m" ] && [ "$now_m" -lt "$to_m" ] && in_quiet=true
        else
          { [ "$now_m" -ge "$from_m" ] || [ "$now_m" -lt "$to_m" ]; } && in_quiet=true
        fi
      fi
      if [ "$in_quiet" = "false" ]; then
        should_notify=true
        if [ -f "$APPROVAL_LOCK" ]; then
          last_ts=$(cat "$APPROVAL_LOCK" 2>/dev/null)
          now=$(date +%s)
          [ $((now - last_ts)) -lt 10 ] && should_notify=false
        fi
        if [ "$should_notify" = true ]; then
          date +%s > "$APPROVAL_LOCK"
          SOUND=$(jq -r '.soundApproval // "Funk"' "$CONFIG_FILE" 2>/dev/null)
          VOL=$(jq -r '.volumeApproval // 1.0' "$CONFIG_FILE" 2>/dev/null)
          SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"
          [[ "$SOUND" == /* ]] && SOUND_FILE="$SOUND"
          [ -f "$SOUND_FILE" ] && afplay -v "$VOL" "$SOUND_FILE" &
          "$NOTIFIER" --title "⏳ Approval needed" --message "$short_cmd"
        fi
      fi
    fi
    ;;
  TodoWrite)
    action_label="Updating tasks"
    ;;
  TodoRead)
    action_label="Reading tasks"
    ;;
  WebSearch|web_search)
    query=$(echo "$tool_input" | jq -r '.query // empty')
    short_q=$(echo "$query" | cut -c1-35)
    action_label="Searching: $short_q"
    ;;
  WebFetch|web_fetch)
    url=$(echo "$tool_input" | jq -r '.url // empty')
    # Show just the domain
    domain=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
    action_label="Fetching $domain"
    ;;
  mcp__*)
    # Strip "mcp__" prefix and tool suffix for readability
    short_name=$(echo "$tool_name" | sed 's/^mcp__//' | sed 's/_/ /g')
    action_label="MCP: $short_name"
    ;;
  Task)
    action_label="Spawning agent"
    ;;
  *)
    action_label="$tool_name"
    ;;
esac

# Write current action
jq -n \
  --arg label "$action_label" \
  --arg tool "$tool_name" \
  --arg session "$session_id" \
  --argjson ts "$(date +%s)" \
  '{label: $label, tool: $tool, session_id: $session, ts: $ts}' \
  > "$ACTION_FILE" 2>/dev/null

# --- If TodoWrite, also persist the todo list ---
if [ "$tool_name" = "TodoWrite" ]; then
  todos=$(echo "$tool_input" | jq -c '.todos // []')
  echo "$todos" > "$TODOS_FILE" 2>/dev/null
fi

# --- Long-running task timers (one per threshold) ---
LR_ENABLED=$(jq -r '.enableLongRunning // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$LR_ENABLED" = "true" ] && [ -x "$NOTIFIER" ] && [ -n "$session_id" ]; then
  LR_SOUND=$(jq -r '.soundLongRunning // "Glass"' "$CONFIG_FILE" 2>/dev/null)
  LR_VOL=$(jq -r '.volumeLongRunning // 1.0' "$CONFIG_FILE" 2>/dev/null)
  LR_PREFIX=$(jq -r '.titlePrefix // "Claude Code"' "$CONFIG_FILE" 2>/dev/null)
  [ -z "$LR_PREFIX" ] && LR_PREFIX="Claude Code"
  LR_SOUND_FILE="/System/Library/Sounds/${LR_SOUND}.aiff"
  [[ "$LR_SOUND" == /* ]] && LR_SOUND_FILE="$LR_SOUND"

  # Read thresholds array; fall back to single longRunningMinutes for old configs
  LR_THRESHOLDS=$(jq -r '(.longRunningThresholds // [.longRunningMinutes // 10]) | .[]' "$CONFIG_FILE" 2>/dev/null)

  for LR_MINUTES in $LR_THRESHOLDS; do
    LR_PID_FILE="/tmp/claude-longtimer-${session_id}-${LR_MINUTES}.pid"
    existing_pid=""
    [ -f "$LR_PID_FILE" ] && existing_pid=$(cat "$LR_PID_FILE" 2>/dev/null)
    if [ -z "$existing_pid" ] || ! kill -0 "$existing_pid" 2>/dev/null; then
      (
        sleep $((LR_MINUTES * 60))
        QE=$(jq -r '.quietEnabled // false' "$CONFIG_FILE" 2>/dev/null)
        if [ "$QE" = "true" ]; then
          QF=$(jq -r '.quietFrom // "22:00"' "$CONFIG_FILE" 2>/dev/null)
          QT=$(jq -r '.quietTo // "08:00"' "$CONFIG_FILE" 2>/dev/null)
          now_m=$((10#$(date +%H) * 60 + 10#$(date +%M)))
          from_m=$((10#${QF%%:*} * 60 + 10#${QF##*:}))
          to_m=$((10#${QT%%:*} * 60 + 10#${QT##*:}))
          in_q=false
          if [ "$from_m" -le "$to_m" ]; then
            [ "$now_m" -ge "$from_m" ] && [ "$now_m" -lt "$to_m" ] && in_q=true
          else
            { [ "$now_m" -ge "$from_m" ] || [ "$now_m" -lt "$to_m" ]; } && in_q=true
          fi
          [ "$in_q" = "true" ] && exit 0
        fi
        [ -f "$LR_SOUND_FILE" ] && afplay -v "$LR_VOL" "$LR_SOUND_FILE" &
        "$NOTIFIER" \
          --title "⏱ $LR_PREFIX" \
          --subtitle "Still running — ${LR_MINUTES}m elapsed" \
          --message "A task is taking longer than expected."
        rm -f "$LR_PID_FILE"
      ) &
      echo $! > "$LR_PID_FILE"
    fi
  done
fi

# Exit 0 — never block tool execution
exit 0
