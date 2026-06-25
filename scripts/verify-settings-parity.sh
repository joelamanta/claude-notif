#!/usr/bin/env bash
# Verify saved Noto settings match what live hooks would send.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-$HOME/.noto/notifications.json}"
SAMPLE="Noto is working. This is the second sentence you should see. This third sentence only appears in Full preview mode."

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Missing config: $CONFIG_FILE"
  exit 1
fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib" && pwd)"
source "$LIB_DIR/read-config.sh"

check_profile() {
  local profile="$1"
  local default_title="$2"
  local default_sound="$3"

  NOTIF_PROFILE="$profile"
  local title sound preview body
  title="$(cfg_val titlePrefix "$default_title")"
  [ -z "$title" ] && title="$default_title"
  sound="$(cfg_val soundDone "$default_sound")"
  preview="$(cfg_val previewLength "sentence")"
  body="$(preview_body "$SAMPLE" "$preview")"

  echo "[$profile]"
  echo "  title:   $title"
  echo "  sound:   $sound"
  echo "  preview: $preview"
  echo "  body:    $body"
  echo
}

echo "Config: $CONFIG_FILE"
echo "Sample: $SAMPLE"
echo

check_profile claude "Claude Code" "Ping"
check_profile cursor "Cursor" "Purr"
check_profile codex "Codex" "Hero"
