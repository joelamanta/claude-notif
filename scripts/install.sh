#!/usr/bin/env bash
# NOTE: set -e is intentionally placed AFTER the header prints,
# so users always see output before any silent failure can occur.

PACKAGE_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
APP_NAME="Noto"
APP_DEST="$HOME/Applications/${APP_NAME}.app"
OLD_APP_DEST="$HOME/Applications/Claude Notif.app"
HOOKS_DIR="$HOME/.claude/hooks"
CONFIG_FILE="$HOME/.noto/notifications.json"
OLD_CONFIG_FILE="$HOME/.claude/notifications.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
VERSION_FILE="$HOME/.noto/version"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.noto.updater.plist"
OLD_LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claudenotif.updater.plist"
UPDATER_SCRIPT="$HOME/.noto/updater.sh"
NOTIFIER="$HOME/Applications/Noto.app/Contents/MacOS/Noto"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

IS_UPDATE=false
[[ "$1" == "--update" ]] && IS_UPDATE=true

bold="\033[1m"
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

step() { echo -e "${bold}→ $1${reset}"; }
ok()   { echo -e "${green}  ✓ $1${reset}"; }
warn() { echo -e "${yellow}  ⚠ $1${reset}"; }
fail() { echo -e "${red}  ✗ $1${reset}"; exit 1; }

if [ "$IS_UPDATE" = false ]; then
  echo ""
  echo -e "${bold}Noto installer${reset}"
  echo "─────────────────────────────────"
fi

set -e

step "Checking platform"
[[ "$(uname)" == "Darwin" ]] || fail "macOS only. Exiting."
ok "macOS detected"

step "Checking dependencies"
command -v swiftc >/dev/null 2>&1 || fail "Xcode Command Line Tools required.\nRun: xcode-select --install"
ok "swiftc found"
command -v jq >/dev/null 2>&1 || fail "jq is required.\nRun: brew install jq"
ok "jq found"

PACKAGE_VERSION=$(jq -r '.version' "$PACKAGE_DIR/package.json")

step "Compiling Noto.app"
BUILD_DIR="$(mktemp -d)"
SWIFT_SOURCES="$PACKAGE_DIR/src/ClaudeNotifier.swift $PACKAGE_DIR/src/TodoStore.swift $PACKAGE_DIR/src/NotesStore.swift $PACKAGE_DIR/src/NotesMarkdown.swift"
SWIFT_FLAGS="-parse-as-library -framework SwiftUI -framework AppKit -framework Foundation -framework UserNotifications"
BINARY_PATH=""

if swiftc $SWIFT_FLAGS \
     -target arm64-apple-macosx12.0 \
     -o "$BUILD_DIR/Noto-arm64" \
     $SWIFT_SOURCES 2>/dev/null && \
   swiftc $SWIFT_FLAGS \
     -target x86_64-apple-macosx12.0 \
     -o "$BUILD_DIR/Noto-x86_64" \
     $SWIFT_SOURCES 2>/dev/null; then
  lipo -create "$BUILD_DIR/Noto-arm64" "$BUILD_DIR/Noto-x86_64" -output "$BUILD_DIR/Noto"
  BINARY_PATH="$BUILD_DIR/Noto"
  ok "Universal binary (arm64 + x86_64)"
else
  swiftc $SWIFT_FLAGS \
    -o "$BUILD_DIR/Noto" \
    $SWIFT_SOURCES 2>/dev/null || \
    fail "Swift compilation failed. Ensure Xcode Command Line Tools are installed:\n  xcode-select --install"
  BINARY_PATH="$BUILD_DIR/Noto"
  warn "Built for native architecture only"
fi

step "Assembling app bundle"
rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS"
mkdir -p "$APP_DEST/Contents/Resources"
cp "$BINARY_PATH"                     "$APP_DEST/Contents/MacOS/Noto"
cp "$PACKAGE_DIR/src/Info.plist"      "$APP_DEST/Contents/Info.plist"
cp "$PACKAGE_DIR/assets/AppIcon.icns" "$APP_DEST/Contents/Resources/AppIcon.icns"
chmod +x "$APP_DEST/Contents/MacOS/Noto"
ok "Bundle assembled at ~/Applications/Noto.app"

step "Signing app"
codesign --deep --force --sign - "$APP_DEST" 2>/dev/null
ok "Ad-hoc signature applied"

step "Registering with Launch Services"
[ -f "$LSREGISTER" ] && "$LSREGISTER" -f "$APP_DEST" 2>/dev/null
ok "Registered"

step "Removing legacy Claude Notif.app"
if [ -d "$OLD_APP_DEST" ]; then
  pkill -f "Claude Notif.app/Contents/MacOS" 2>/dev/null || true
  [ -f "$LSREGISTER" ] && "$LSREGISTER" -u "$OLD_APP_DEST" 2>/dev/null || true
  rm -rf "$OLD_APP_DEST"
  ok "Removed ~/Applications/Claude Notif.app"
else
  ok "Legacy app not found — skipped"
fi

step "Writing config"
mkdir -p "$HOME/.noto"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$OLD_CONFIG_FILE" ]; then
  cp "$OLD_CONFIG_FILE" "$CONFIG_FILE"
  ok "Migrated ~/.claude/notifications.json → ~/.noto/notifications.json"
elif [ ! -f "$CONFIG_FILE" ]; then
  printf '{"enabled":true,"soundDone":"Ping","soundError":"Basso","soundInterrupt":"Pop"}\n' > "$CONFIG_FILE"
  ok "Created ~/.noto/notifications.json"
else
  ok "Config already exists — skipped"
fi

step "Installing hooks"
mkdir -p "$HOOKS_DIR"
mkdir -p "$HOME/.cursor/hooks"
mkdir -p "$HOME/.codex/hooks"

cp "$PACKAGE_DIR/hooks/lib/read-config.sh" "$HOOKS_DIR/noto-read-config.sh"
cp "$PACKAGE_DIR/hooks/lib/read-config.sh" "$HOME/.cursor/hooks/read-config.sh"
cp "$PACKAGE_DIR/hooks/lib/read-config.sh" "$HOME/.codex/hooks/read-config.sh"
cp "$PACKAGE_DIR/hooks/lib/preview-text.py" "$HOOKS_DIR/preview-text.py"
cp "$PACKAGE_DIR/hooks/lib/preview-text.py" "$HOME/.cursor/hooks/preview-text.py"
cp "$PACKAGE_DIR/hooks/lib/preview-text.py" "$HOME/.codex/hooks/preview-text.py"

sed "s|NOTIFIER=.*|NOTIFIER=\"$NOTIFIER\"|" \
  "$PACKAGE_DIR/hooks/stop.sh" > "$HOOKS_DIR/noto-stop.sh"
sed "s|NOTIFIER=.*|NOTIFIER=\"$NOTIFIER\"|" \
  "$PACKAGE_DIR/hooks/pre-tool-use.sh" > "$HOOKS_DIR/noto-pre-tool-use.sh"

for hook in after-agent-response.sh pre-tool-use.sh stop.sh before-shell-execution.sh before-mcp-execution.sh; do
  sed "s|NOTIFIER=.*|NOTIFIER=\"$NOTIFIER\"|" \
    "$PACKAGE_DIR/hooks/cursor/$hook" > "$HOME/.cursor/hooks/$hook"
done
cp "$PACKAGE_DIR/hooks/cursor/check-approval-needed.py" "$HOME/.cursor/hooks/check-approval-needed.py"
chmod +x "$HOME/.cursor/hooks/check-approval-needed.py"

for hook in pre-tool-use.sh permission-request.sh stop.sh; do
  sed "s|NOTIFIER=.*|NOTIFIER=\"$NOTIFIER\"|" \
    "$PACKAGE_DIR/hooks/codex/$hook" > "$HOME/.codex/hooks/$hook"
done

chmod +x "$HOOKS_DIR"/noto-*.sh "$HOME/.cursor/hooks"/*.sh "$HOME/.codex/hooks"/*.sh

rm -f "$HOOKS_DIR/claude-notif-stop.sh" "$HOOKS_DIR/claude-notif-pre-tool-use.sh" "$HOOKS_DIR/claude-notif-read-config.sh"

if [ ! -f "$HOME/.cursor/hooks.json" ]; then
  cat > "$HOME/.cursor/hooks.json" <<'JSON'
{
  "version": 1,
  "hooks": {
    "preToolUse": [{ "command": "hooks/pre-tool-use.sh" }],
    "beforeShellExecution": [{ "command": "hooks/before-shell-execution.sh" }],
    "beforeMCPExecution": [{ "command": "hooks/before-mcp-execution.sh" }],
    "afterAgentResponse": [{ "command": "hooks/after-agent-response.sh" }],
    "stop": [{ "command": "hooks/stop.sh" }]
  }
}
JSON
fi

cp "$PACKAGE_DIR/hooks/codex/hooks.json" "$HOME/.codex/hooks.json"
ok "Hooks written for Claude, Cursor, and Codex"

step "Updating ~/.claude/settings.json"
python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except json.JSONDecodeError:
        pass

hooks = settings.setdefault("hooks", {})
legacy = ["claude-notif-stop", "claude-notif-pre-tool-use"]
new = {
    "Stop": "bash $HOME/.claude/hooks/noto-stop.sh",
    "PreToolUse": "bash $HOME/.claude/hooks/noto-pre-tool-use.sh",
}

for event, entries in list(hooks.items()):
    hooks[event] = [
        group for group in entries
        if not any(
            any(marker in h.get("command", "") for marker in legacy)
            for h in group.get("hooks", [])
        )
    ]

def add_hook(event, command):
    entries = hooks.setdefault(event, [])
    for group in entries:
        for h in group.get("hooks", []):
            if command in h.get("command", ""):
                return
    entries.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}]
    })

for event, command in new.items():
    add_hook(event, command)

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
ok "settings.json updated"

echo "$PACKAGE_VERSION" > "$VERSION_FILE"
ok "Version recorded ($PACKAGE_VERSION)"

step "Installing auto-updater"
cp "$PACKAGE_DIR/scripts/updater.sh" "$UPDATER_SCRIPT"
chmod +x "$UPDATER_SCRIPT"
launchctl unload "$OLD_LAUNCH_AGENT" 2>/dev/null || true
rm -f "$OLD_LAUNCH_AGENT"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.noto.updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$UPDATER_SCRIPT</string>
    </array>
    <key>StartInterval</key>
    <integer>86400</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/.noto/updater.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.noto/updater.log</string>
</dict>
</plist>
PLIST

launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PLIST" 2>/dev/null
ok "Auto-updater scheduled (runs daily)"

if [ "$IS_UPDATE" = false ]; then
  step "Launching Noto"
  pkill -f "Noto.app/Contents/MacOS/Noto" 2>/dev/null || true
  sleep 0.3
  open "$APP_DEST"
fi

rm -rf "$BUILD_DIR"

if [ "$IS_UPDATE" = false ]; then
  echo ""
  echo -e "${green}${bold}Installation complete.${reset}"
  echo ""
  echo "  App:    ~/Applications/Noto.app"
  echo "  Config: ~/.noto/notifications.json"
  echo "  Hooks:  ~/.claude/hooks/noto-*.sh"
  echo "  Auto-update: daily via LaunchAgent"
  echo ""
  echo "The settings window is now open."
  echo "Grant notification permission if macOS prompts you."
  echo ""
  echo "To uninstall: npx noto uninstall"
  echo ""
fi
