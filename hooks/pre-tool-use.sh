#!/usr/bin/env bash
# Claude Code PreToolUse hook

NOTIF_PROFILE="claude"
ACTION_FILE="/tmp/claude-current-action.json"
TODOS_FILE="/tmp/claude-todos.json"
APPROVAL_LOCK="/tmp/noto-claude-approval.lock"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -x "$NOTIFIER" ] || exit 0
if [ -f "$HOME/.claude/hooks/noto-read-config.sh" ]; then
  source "$HOME/.claude/hooks/noto-read-config.sh"
else
  source "$HOOK_DIR/lib/read-config.sh"
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

    if cfg_enabled && [ "$(cfg_val enableApproval true)" != "false" ] && ! cfg_in_quiet_hours; then
      should_notify=true
      if [ -f "$APPROVAL_LOCK" ]; then
        last_ts=$(cat "$APPROVAL_LOCK" 2>/dev/null)
        now=$(date +%s)
        [ $((now - last_ts)) -lt 10 ] && should_notify=false
      fi
      if [ "$should_notify" = true ]; then
        date +%s > "$APPROVAL_LOCK"
        ( "$NOTIFIER" \
            --title "⏳ Approval needed" \
            --message "$short_cmd" \
            --sound "$(cfg_val soundApproval "Funk")" \
            --volume "$(cfg_val volumeApproval "1.0")" \
            </dev/null >/dev/null 2>&1 ) &
      fi
    fi
    ;;
  TodoWrite) action_label="Updating tasks" ;;
  TodoRead) action_label="Reading tasks" ;;
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
  Task) action_label="Spawning agent" ;;
  *) action_label="$tool_name" ;;
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

start_long_timers "claude" "$session_id" "/tmp/noto-claude-pending.json" "Claude" \
  '.claude.longRunningThresholds // .claude.longRunningMinutes // .longRunningThresholds // [.longRunningMinutes // 10] | if type == "array" then .[] else . end'

exit 0
