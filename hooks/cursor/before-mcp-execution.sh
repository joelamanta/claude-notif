#!/usr/bin/env bash
# Cursor beforeMCPExecution — approval notification only when MCP tool is not allowlisted.

NOTIF_PROFILE="cursor"
APPROVAL_LOCK="/tmp/noto-cursor-approval.lock"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HOOK_DIR/check-approval-needed.py"

[ -x "$NOTIFIER" ] || exit 0
if [ -f "$HOME/.cursor/hooks/read-config.sh" ]; then
  source "$HOME/.cursor/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // .toolName // empty' 2>/dev/null)
provider=$(echo "$input" | jq -r '.provider_identifier // .providerIdentifier // .server_name // .serverName // empty' 2>/dev/null)

if [ -z "$provider" ] && [[ "$tool_name" == mcp__* ]]; then
  provider=$(echo "$tool_name" | awk -F'__' '{print $2}')
fi

needs_approval=0
if [ -f "$CHECKER" ]; then
  if printf '%s' "$input" | python3 "$CHECKER" json-mcp; then
    needs_approval=1
  elif [ -n "$provider" ] && [ -n "$tool_name" ] && python3 "$CHECKER" mcp "$provider" "$tool_name"; then
    needs_approval=1
  fi
fi

if [ "$needs_approval" -eq 1 ] && cfg_enabled && [ "$(cfg_val enableApproval true)" != "false" ] && ! cfg_in_quiet_hours; then
  label="$tool_name"
  [ -n "$provider" ] && label="${provider}: ${tool_name}"
  message=$(echo "$label" | cut -c1-40)
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
        --message "$message" \
        --sound "$(cfg_val soundApproval "Funk")" \
        --volume "$(cfg_val volumeApproval "1.0")" \
        </dev/null >/dev/null 2>&1 ) &
    disown 2>/dev/null
  fi
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
