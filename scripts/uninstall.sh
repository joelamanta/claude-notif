#!/usr/bin/env bash

APP_DEST="$HOME/Applications/Noto.app"
OLD_APP_DEST="$HOME/Applications/Claude Notif.app"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
CONFIG_FILE="$HOME/.noto/notifications.json"
OLD_CONFIG_FILE="$HOME/.claude/notifications.json"
VERSION_FILE="$HOME/.noto/version"
UPDATER_SCRIPT="$HOME/.noto/updater.sh"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.noto.updater.plist"
OLD_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claudenotif.updater.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

bold="\033[1m"
green="\033[32m"
yellow="\033[33m"
reset="\033[0m"

step() { echo -e "${bold}→ $1${reset}"; }
ok()   { echo -e "${green}  ✓ $1${reset}"; }

echo ""
echo -e "${bold}Noto uninstaller${reset}"
echo "─────────────────────────────────"

step "Removing auto-updater"
launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
launchctl unload "$OLD_LAUNCH_AGENT" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_PLIST" "$OLD_LAUNCH_AGENT" "$UPDATER_SCRIPT"
ok "Auto-updater removed"

step "Stopping Noto"
pkill -f "Noto.app/Contents/MacOS/Noto" 2>/dev/null && ok "Stopped" || ok "Not running"
pkill -f "Claude Notif.app/Contents/MacOS" 2>/dev/null || true

step "Deregistering from Launch Services"
[ -f "$LSREGISTER" ] && [ -d "$APP_DEST" ] && "$LSREGISTER" -u "$APP_DEST" 2>/dev/null
[ -f "$LSREGISTER" ] && [ -d "$OLD_APP_DEST" ] && "$LSREGISTER" -u "$OLD_APP_DEST" 2>/dev/null
ok "Deregistered"

step "Removing app"
rm -rf "$APP_DEST" "$OLD_APP_DEST"
ok "Removed Noto.app and legacy Claude Notif.app"

step "Removing hook scripts"
rm -f "$HOOKS_DIR/noto-stop.sh" "$HOOKS_DIR/noto-pre-tool-use.sh" "$HOOKS_DIR/noto-read-config.sh"
rm -f "$HOOKS_DIR/claude-notif-stop.sh" "$HOOKS_DIR/claude-notif-pre-tool-use.sh" "$HOOKS_DIR/claude-notif-read-config.sh"
ok "Hook scripts removed"

step "Cleaning ~/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(0)

markers = ["noto-stop", "noto-pre-tool-use", "claude-notif-stop", "claude-notif-pre-tool-use"]

for event, entries in settings.get("hooks", {}).items():
    settings["hooks"][event] = [
        group for group in entries
        if not any(
            any(marker in h.get("command", "") for marker in markers)
            for h in group.get("hooks", [])
        )
    ]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
  ok "Hook entries removed from settings.json"
else
  ok "settings.json not found — skipped"
fi

rm -f "$VERSION_FILE"

echo ""
read -p "  Remove ~/.noto/notifications.json? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  rm -f "$CONFIG_FILE"
  ok "Config removed"
else
  ok "Config kept"
fi

echo ""
echo -e "${green}${bold}Uninstall complete.${reset}"
echo ""
