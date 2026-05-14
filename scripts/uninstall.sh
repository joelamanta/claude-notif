#!/usr/bin/env bash

APP_DEST="$HOME/Applications/Claude Notif.app"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
CONFIG_FILE="$HOME/.claude/notifications.json"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

bold="\033[1m"
green="\033[32m"
yellow="\033[33m"
reset="\033[0m"

step() { echo -e "${bold}→ $1${reset}"; }
ok()   { echo -e "${green}  ✓ $1${reset}"; }
warn() { echo -e "${yellow}  ⚠ $1${reset}"; }

echo ""
echo -e "${bold}claude-notif uninstaller${reset}"
echo "─────────────────────────────────"

# Kill running instance
step "Stopping Claude Notif"
pkill -f "Claude Notif" 2>/dev/null && ok "Stopped" || ok "Not running"

# Deregister from Launch Services
step "Deregistering from Launch Services"
[ -f "$LSREGISTER" ] && [ -d "$APP_DEST" ] && "$LSREGISTER" -u "$APP_DEST" 2>/dev/null
ok "Deregistered"

# Remove app
step "Removing app"
if [ -d "$APP_DEST" ]; then
  rm -rf "$APP_DEST"
  ok "Removed ~/Applications/Claude Notif.app"
else
  ok "App not found — skipped"
fi

# Remove hooks
step "Removing hook scripts"
rm -f "$HOOKS_DIR/claude-notif-stop.sh" "$HOOKS_DIR/claude-notif-pre-tool-use.sh"
ok "Hook scripts removed"

# Remove hook entries from settings.json
step "Cleaning ~/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(0)

markers = ["claude-notif-stop", "claude-notif-pre-tool-use"]

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

# Config file — ask
echo ""
read -p "  Remove ~/.claude/notifications.json? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  rm -f "$CONFIG_FILE"
  ok "Config removed"
else
  ok "Config kept"
fi

echo ""
echo -e "${green}${bold}Uninstall complete.${reset}"
echo ""
