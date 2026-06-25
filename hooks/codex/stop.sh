#!/usr/bin/env bash
# Codex Stop hook — done/error/interrupt notifications

NOTIF_PROFILE="codex"
CONFIG_FILE="$HOME/.noto/notifications.json"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$HOME/.codex/hooks/read-config.sh" ]; then
  source "$HOME/.codex/hooks/read-config.sh"
else
  source "$HOOK_DIR/../lib/read-config.sh"
fi

input=$(cat)
last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)
finish_long_timers "codex"

[ -x "$NOTIFIER" ] || exit 0

cfg_should_notify || exit 0
cfg_in_quiet_hours && exit 0

TITLE_PREFIX="$(cfg_val titlePrefix "Codex")"
[ -z "$TITLE_PREFIX" ] && TITLE_PREFIX="Codex"
PREVIEW="$(cfg_val previewLength "sentence")"

body=""
if [ -n "$last_msg" ] && [ "$last_msg" != "null" ]; then
  raw_text=$(echo "$last_msg" \
    | sed 's/\*\*//g; s/\*//g; s/^#\+[[:space:]]//g; s/`//g' \
    | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//')
  body=$(preview_body "$raw_text" "$PREVIEW")
fi
[ -z "$body" ] && body="Done."

sound="$(cfg_val soundDone "Hero")"
vol="$(cfg_val volumeDone "1.0")"
title="$TITLE_PREFIX"

# Codex Stop has no reason field like Cursor — treat as done notification
[ "$(cfg_val enableDone true)" = "false" ] && exit 0

notify_queue "/tmp/noto-codex-pending.json" "codex" "Codex" \
  "$title" "" "$body" "$sound" "$vol" "done"

exit 0
