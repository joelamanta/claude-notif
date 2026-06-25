#!/usr/bin/env bash
# Codex PreToolUse hook

NOTIF_PROFILE="codex"
ACTION_FILE="/tmp/codex-current-action.json"
APPROVAL_LOCK="/tmp/noto-codex-approval.lock"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -x "$NOTIFIER" ] || exit 0
if [ -f "$HOME/.codex/hooks/read-config.sh" ]; then
  source "$HOME/.codex/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -c '.tool_input // {}')
session_id=$(echo "$input" | jq -r '.session_id // empty')

action_label=""
case "$tool_name" in
  Bash)
    cmd=$(echo "$tool_input" | jq -r '.command // empty')
    short_cmd=$(echo "$cmd" | head -1 | cut -c1-40)
    action_label="Bash: $short_cmd"
    ;;
  apply_patch|Edit|Write)
    action_label="Editing files"
    ;;
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

start_long_timers "codex" "$session_id" "/tmp/noto-codex-pending.json" "Codex" \
  '.codex.longRunningThresholds // .codex.longRunningMinutes // [.longRunningMinutes // 10] | if type == "array" then .[] else . end'

exit 0
