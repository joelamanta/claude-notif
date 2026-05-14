#!/usr/bin/env bash
set -e

PACKAGE_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
APP_NAME="Claude Notif"
APP_DEST="$HOME/Applications/${APP_NAME}.app"
HOOKS_DIR="$HOME/.claude/hooks"
CONFIG_FILE="$HOME/.claude/notifications.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

bold="\033[1m"
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

step() { echo -e "${bold}→ $1${reset}"; }
ok()   { echo -e "${green}  ✓ $1${reset}"; }
warn() { echo -e "${yellow}  ⚠ $1${reset}"; }
fail() { echo -e "${red}  ✗ $1${reset}"; exit 1; }

echo ""
echo -e "${bold}claude-notif installer${reset}"
echo "─────────────────────────────────"

# 1. Platform check
step "Checking platform"
[[ "$(uname)" == "Darwin" ]] || fail "macOS only. Exiting."
ok "macOS detected"

# 2. Dependency checks
step "Checking dependencies"
command -v swiftc >/dev/null 2>&1 || fail "Xcode Command Line Tools required.\nRun: xcode-select --install"
ok "swiftc found"
command -v jq >/dev/null 2>&1 || fail "jq is required.\nRun: brew install jq"
ok "jq found"

# 3. Compile Swift source
step "Compiling Claude Notif.app"
BUILD_DIR="$(mktemp -d)"

SWIFT_FLAGS="-parse-as-library -framework SwiftUI -framework AppKit -framework Foundation -framework UserNotifications"

BINARY_PATH=""

# Try universal binary first
if swiftc $SWIFT_FLAGS \
     -target arm64-apple-macosx12.0 \
     -o "$BUILD_DIR/ClaudeCode-arm64" \
     "$PACKAGE_DIR/src/ClaudeNotifier.swift" 2>/dev/null && \
   swiftc $SWIFT_FLAGS \
     -target x86_64-apple-macosx12.0 \
     -o "$BUILD_DIR/ClaudeCode-x86_64" \
     "$PACKAGE_DIR/src/ClaudeNotifier.swift" 2>/dev/null; then
  lipo -create "$BUILD_DIR/ClaudeCode-arm64" "$BUILD_DIR/ClaudeCode-x86_64" \
       -output "$BUILD_DIR/ClaudeCode"
  BINARY_PATH="$BUILD_DIR/ClaudeCode"
  ok "Universal binary (arm64 + x86_64)"
else
  # Fall back to native arch
  swiftc $SWIFT_FLAGS \
    -o "$BUILD_DIR/ClaudeCode" \
    "$PACKAGE_DIR/src/ClaudeNotifier.swift" 2>/dev/null || \
    fail "Swift compilation failed. Ensure Xcode Command Line Tools are installed:\n  xcode-select --install"
  BINARY_PATH="$BUILD_DIR/ClaudeCode"
  warn "Built for native architecture only"
fi

# 4. Assemble app bundle
step "Assembling app bundle"
rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS"
mkdir -p "$APP_DEST/Contents/Resources"

cp "$BINARY_PATH"                         "$APP_DEST/Contents/MacOS/ClaudeCode"
cp "$PACKAGE_DIR/src/Info.plist"          "$APP_DEST/Contents/Info.plist"
cp "$PACKAGE_DIR/assets/AppIcon.icns"     "$APP_DEST/Contents/Resources/AppIcon.icns"
chmod +x "$APP_DEST/Contents/MacOS/ClaudeCode"
ok "Bundle assembled at ~/Applications/Claude Notif.app"

# 5. Sign
step "Signing app"
codesign --deep --force --sign - "$APP_DEST" 2>/dev/null
ok "Ad-hoc signature applied"

# 6. Register with Launch Services
step "Registering with Launch Services"
[ -f "$LSREGISTER" ] && "$LSREGISTER" -f "$APP_DEST" 2>/dev/null
ok "Registered"

# 7. Default config
step "Writing default config"
mkdir -p "$HOME/.claude"
if [ ! -f "$CONFIG_FILE" ]; then
  printf '{"enabled":true,"soundDone":"Ping","soundError":"Basso","soundInterrupt":"Pop"}\n' > "$CONFIG_FILE"
  ok "Created ~/.claude/notifications.json"
else
  ok "Config already exists — skipped"
fi

# 8. Install hook scripts
step "Installing hooks"
mkdir -p "$HOOKS_DIR"

sed 's|NOTIFIER=.*|NOTIFIER="$HOME/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode"|' \
  "$PACKAGE_DIR/hooks/stop.sh" > "$HOOKS_DIR/claude-notif-stop.sh"
cp "$PACKAGE_DIR/hooks/pre-tool-use.sh" "$HOOKS_DIR/claude-notif-pre-tool-use.sh"
chmod +x "$HOOKS_DIR/claude-notif-stop.sh" "$HOOKS_DIR/claude-notif-pre-tool-use.sh"
ok "Hooks written to ~/.claude/hooks/claude-notif-*.sh"

# 9. Merge hooks into settings.json
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

def add_hook(event, command):
    entries = hooks.setdefault(event, [])
    for group in entries:
        for h in group.get("hooks", []):
            if command in h.get("command", ""):
                return  # already registered
    entries.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}]
    })

add_hook("Stop",       "bash $HOME/.claude/hooks/claude-notif-stop.sh")
add_hook("PreToolUse", "bash $HOME/.claude/hooks/claude-notif-pre-tool-use.sh")

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF

ok "settings.json updated"

# 10. Launch
step "Launching Claude Notif"
open "$APP_DEST"

# Cleanup
rm -rf "$BUILD_DIR"

echo ""
echo -e "${green}${bold}Installation complete.${reset}"
echo ""
echo "  App:    ~/Applications/Claude Notif.app"
echo "  Config: ~/.claude/notifications.json"
echo "  Hooks:  ~/.claude/hooks/claude-notif-*.sh"
echo ""
echo "The settings window is now open."
echo "Grant notification permission if macOS prompts you."
echo ""
echo "To uninstall: npx claude-notif uninstall"
echo ""
