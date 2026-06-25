#!/usr/bin/env bash
# Cursor beforeShellExecution — approval notification only when command is not allowlisted.

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
command=$(echo "$input" | jq -r '.command // empty' 2>/dev/null)

echo "$command" | grep -q "Noto\|notifications\.json" && {
  printf '%s\n' '{"permission":"allow"}'
  exit 0
}

needs_approval=0
if [ -f "$CHECKER" ]; then
  if printf '%s' "$input" | python3 "$CHECKER" json-shell; then
    needs_approval=1
  fi
fi

if [ "$needs_approval" -eq 1 ] && cfg_enabled && [ "$(cfg_val enableApproval true)" != "false" ] && ! cfg_in_quiet_hours; then
  short_cmd=$(echo "$command" | head -1 | cut -c1-40)
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
    disown 2>/dev/null
  fi
fi

printf '%s\n' '{"permission":"allow"}'
exit 0
