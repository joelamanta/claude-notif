#!/usr/bin/env bash
# Claude Code PreToolUse hook
# Writes current tool action to /tmp/claude-current-action.json
# Fires approval notification for Bash commands (debounced 10s)

ACTION_FILE="/tmp/claude-current-action.json"
TODOS_FILE="/tmp/claude-todos.json"
APPROVAL_LOCK="/tmp/claude-notif-approval.lock"
CONFIG_FILE="$HOME/.claude/notifications.json"
NOTIFIER="$HOME/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode"

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -c '.tool_input // {}')
session_id=$(echo "$input" | jq -r '.session_id // empty')

action_label=""
case "$tool_name" in
  Read)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    action_label="Reading $(basename "$file_path")"
    ;;
  Edit|MultiEdit)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    action_label="Editing $(basename "$file_path")"
    ;;
  Write)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    action_label="Writing $(basename "$file_path")"
    ;;
  Bash)
    cmd=$(echo "$tool_input" | jq -r '.command // empty')
    short_cmd=$(echo "$cmd" | head -1 | cut -c1-40)
    action_label="Bash: $short_cmd"

    # Approval notification — debounced 10s
    ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    if [ "$ENABLED" != "false" ] && [ -x "$NOTIFIER" ]; then
      should_notify=true
      if [ -f "$APPROVAL_LOCK" ]; then
        last_ts=$(cat "$APPROVAL_LOCK" 2>/dev/null)
        now=$(date +%s)
        [ $((now - last_ts)) -lt 10 ] && should_notify=false
      fi

      if [ "$should_notify" = true ]; then
        date +%s > "$APPROVAL_LOCK"
        SOUND=$(jq -r '.soundApproval // "Funk"' "$CONFIG_FILE" 2>/dev/null)
        SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"
        [[ "$SOUND" == /* ]] && SOUND_FILE="$SOUND"
        [ -f "$SOUND_FILE" ] && afplay "$SOUND_FILE" &
        "$NOTIFIER" \
          --title "⏳ Approval needed" \
          --message "$short_cmd" &
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
    action_label="Searching: $(echo "$query" | cut -c1-35)"
    ;;
  WebFetch|web_fetch)
    url=$(echo "$tool_input" | jq -r '.url // empty')
    domain=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
    action_label="Fetching $domain"
    ;;
  mcp__*)
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

jq -n \
  --arg label "$action_label" \
  --arg tool "$tool_name" \
  --arg session "$session_id" \
  --argjson ts "$(date +%s)" \
  '{label: $label, tool: $tool, session_id: $session, ts: $ts}' \
  > "$ACTION_FILE" 2>/dev/null

if [ "$tool_name" = "TodoWrite" ]; then
  todos=$(echo "$tool_input" | jq -c '.todos // []')
  echo "$todos" > "$TODOS_FILE" 2>/dev/null
fi

exit 0
