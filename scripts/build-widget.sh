#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIDGET_DIR="$ROOT/widget"
SRC="$WIDGET_DIR/NotoTodoWidget/NotoTodoWidget.swift"
PLIST="$WIDGET_DIR/NotoTodoWidget/Info.plist"
APPEX="$WIDGET_DIR/build/NotoTodoWidget.appex"
DEST="$HOME/Library/Widgets/NotoTodoWidget.appex"

step() { printf '\033[1m→ %s\033[0m\n' "$1"; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

step "Building Noto Todo widget"
rm -rf "$WIDGET_DIR/build"
mkdir -p "$APPEX/Contents/MacOS"

swiftc -parse-as-library \
  -framework WidgetKit -framework SwiftUI -framework AppKit \
  -o "$APPEX/Contents/MacOS/NotoTodoWidget" \
  "$SRC"

cp "$PLIST" "$APPEX/Contents/Info.plist"
/usr/bin/codesign --deep --force --sign - "$APPEX"
ok "Built $APPEX"

step "Installing to ~/Library/Widgets"
mkdir -p "$HOME/Library/Widgets"
rm -rf "$DEST"
cp -R "$APPEX" "$DEST"
ok "Installed $DEST"
echo ""
echo "Add the widget from Notification Center → Edit Widgets → Noto Todo"
