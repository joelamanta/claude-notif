#!/usr/bin/env bash
# Cursor preToolUse hook

NOTIF_PROFILE="cursor"
ACTION_FILE="/tmp/cursor-current-action.json"
TODOS_FILE="/tmp/cursor-todos.json"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -x "$NOTIFIER" ] || exit 0
if [ -f "$HOME/.cursor/hooks/read-config.sh" ]; then
  source "$HOME/.cursor/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

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
  Edit|MultiEdit|StrReplace)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty')
    action_label="Editing $(basename "$file_path")"
    ;;
  Write)
    file_path=$(echo "$tool_input" | jq -r '.path // .file_path // empty')
    action_label="Writing $(basename "$file_path")"
    ;;
  Shell|Bash)
    cmd=$(echo "$tool_input" | jq -r '.command // empty')
    short_cmd=$(echo "$cmd" | head -1 | cut -c1-40)
    action_label="Shell: $short_cmd"
    echo "$cmd" | grep -q "Noto\|notifications\.json" && exit 0
    ;;
  TodoWrite)
    action_label="Updating tasks"
    todos=$(echo "$tool_input" | jq -c '.todos // []')
    echo "$todos" > "$TODOS_FILE" 2>/dev/null
    ;;
  TodoRead) action_label="Reading tasks" ;;
  WebSearch|web_search)
    query=$(echo "$tool_input" | jq -r '.query // .search_term // empty')
    action_label="Searching: $(echo "$query" | cut -c1-35)"
    ;;
  WebFetch|web_fetch)
    url=$(echo "$tool_input" | jq -r '.url // empty')
    domain=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
    action_label="Fetching $domain"
    ;;
  Task) action_label="Spawning agent" ;;
  mcp__*)
    short_name=$(echo "$tool_name" | sed 's/^mcp__//' | sed 's/_/ /g')
    action_label="MCP: $short_name"
    ;;
  *) action_label="$tool_name" ;;
esac

jq -n \
  --arg label "$action_label" \
  --arg tool "$tool_name" \
  --arg session "$session_id" \
  --argjson ts "$(date +%s)" \
  '{label: $label, tool: $tool, session_id: $session, ts: $ts}' \
  > "$ACTION_FILE" 2>/dev/null

start_long_timers "cursor" "$session_id" "/tmp/noto-cursor-pending.json" "Cursor" \
  '.cursor.longRunningThresholds // .cursor.longRunningMinutes // .longRunningThresholds // [.longRunningMinutes // 10] | if type == "array" then .[] else . end'

exit 0
