#!/usr/bin/env bash
# Noto auto-updater — runs daily via LaunchAgent

VERSION_FILE="$HOME/.noto/version"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
LOG_FILE="$HOME/.noto/updater.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

log "Checking for updates..."

INSTALLED=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")
LATEST=$(curl -sf https://registry.npmjs.org/noto/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null)

if [ -z "$LATEST" ]; then
  LATEST=$(curl -sf https://registry.npmjs.org/claude-notif/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null)
fi

if [ -z "$LATEST" ]; then
  log "Could not reach npm registry — skipping."
  exit 0
fi

if [ "$LATEST" = "$INSTALLED" ]; then
  log "Already up to date ($INSTALLED)."
  exit 0
fi

log "Update found: $INSTALLED → $LATEST. Installing..."

npx --yes "noto@$LATEST" --update >> "$LOG_FILE" 2>&1 || \
  npx --yes "claude-notif@$LATEST" --update >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
  echo "$LATEST" > "$VERSION_FILE"
  log "Updated to $LATEST."
  [ -x "$NOTIFIER" ] && "$NOTIFIER" \
    --title "Noto updated" \
    --message "Updated to v$LATEST" &
else
  log "Update failed. Will retry tomorrow."
fi
