#!/usr/bin/env bash
# Codex PermissionRequest hook — approval notifications

NOTIF_PROFILE="codex"
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

cfg_enabled || exit 0
[ "$(cfg_val enableApproval true)" != "false" ] || exit 0
cfg_in_quiet_hours && exit 0

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_input=$(echo "$input" | jq -c '.tool_input // {}')

message=""
case "$tool_name" in
  Bash)
    cmd=$(echo "$tool_input" | jq -r '.command // empty')
    message=$(echo "$cmd" | head -1 | cut -c1-40)
    ;;
  apply_patch|Edit|Write)
    message="File change approval needed"
    ;;
  *)
    message="Approval needed for $tool_name"
    ;;
esac

should_notify=true
if [ -f "$APPROVAL_LOCK" ]; then
  last_ts=$(cat "$APPROVAL_LOCK" 2>/dev/null)
  now=$(date +%s)
  [ $((now - last_ts)) -lt 10 ] && should_notify=false
fi
[ "$should_notify" = false ] && exit 0

date +%s > "$APPROVAL_LOCK"
( "$NOTIFIER" \
    --title "⏳ Approval needed" \
    --message "$message" \
    --sound "$(cfg_val soundApproval "Funk")" \
    --volume "$(cfg_val volumeApproval "1.0")" \
    </dev/null >/dev/null 2>&1 ) &
exit 0
