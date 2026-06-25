#!/usr/bin/env bash
# Cursor stop hook — error/interrupt only

NOTIF_PROFILE="cursor"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$HOME/.cursor/hooks/read-config.sh" ]; then
  source "$HOME/.cursor/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

input=$(cat)
reason=$(echo "$input" | jq -r '.reason // empty' 2>/dev/null)
finish_long_timers "cursor"

[ -x "$NOTIFIER" ] || exit 0

cfg_should_notify || exit 0
cfg_in_quiet_hours && exit 0

TITLE_PREFIX="$(cfg_val titlePrefix "Cursor")"
[ -z "$TITLE_PREFIX" ] && TITLE_PREFIX="Cursor"

case "$reason" in
  *error*)
    [ "$(cfg_val enableError true)" = "false" ] && exit 0
    notify_queue "/tmp/noto-cursor-pending.json" "cursor" "Cursor" \
      "⚠ $TITLE_PREFIX" "" "Something went wrong." \
      "$(cfg_val soundError "Basso")" "$(cfg_val volumeError "1.0")" "alert"
    ;;
  *interrupt*|*cancel*)
    [ "$(cfg_val enableInterrupt true)" = "false" ] && exit 0
    notify_queue "/tmp/noto-cursor-pending.json" "cursor" "Cursor" \
      "⏸ $TITLE_PREFIX" "" "Interrupted." \
      "$(cfg_val soundInterrupt "Pop")" "$(cfg_val volumeInterrupt "1.0")" "alert"
    ;;
  *)
    exit 0
    ;;
esac

exit 0
