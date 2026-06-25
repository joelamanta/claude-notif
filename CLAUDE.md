# claude-notif — Project Rules

## Hook Safety Rules

These rules exist because Claude Code hooks run synchronously in bash. If a hook blocks, Claude cannot execute tools. The notifier must never be the cause of a hang.

### Rules (apply to every hook script and every new feature)

1. **Always check the notifier exists at the top of every hook:**
   ```bash
   [ -x "$NOTIFIER" ] || exit 0
   ```
   Hooks must exit cleanly and silently if the app is missing or broken.

2. **Always background every notifier call:**
   ```bash
   timeout 3 "$NOTIFIER" --title "..." --message "..." &
   ```
   Never call `"$NOTIFIER" ...` without `&`. The hook must not wait for the process to finish.

3. **Always wrap notifier calls with `timeout 3`:**
   Even backgrounded processes can consume resources. `timeout 3` is a hard kill if the notifier hangs.

4. **The Swift app must always exit within 2 seconds in notification mode:**
   `sendNotification()` in `ClaudeNotifier.swift` schedules a forced `exit(0)` via:
   ```swift
   DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exit(0) }
   ```
   This is the last line of defense. Never remove it.

5. **New notification features must not require the process to stay alive for user interaction.**
   Features like "click to open terminal" (action buttons on banners) conflict with fast-exit. Build those features only after all safety rules are confirmed working, and document the trade-off explicitly.

## Build Command

```bash
cd "/Users/teevoteam/Documents/Claude/Projects/Teevo Joel's Claude/Claude Notifications"
swiftc -parse-as-library -framework SwiftUI -framework AppKit -framework Foundation -framework UserNotifications \
  -o "Claude Notif.app/Contents/MacOS/ClaudeCode" "/Users/teevoteam/Documents/Claude/Projects/claude-notif/src/ClaudeNotifier.swift"
codesign --force --sign - "Claude Notif.app"
cp -R "Claude Notif.app" ~/Applications/
pkill ClaudeCode; sleep 0.3; open ~/Applications/"Claude Notif.app"
```

## Known LSP False Positive

SourceKit reports `'main' attribute cannot be used in a module that contains top-level code` — ignore it. Compile with `-parse-as-library` as shown above.

## Publishing

1. Bump version in `package.json` and `src/Info.plist`
2. `git add -A && git commit -m "..." && git push`
3. `npm publish --access public`

## Hard rules for this project
1. NEVER invoke `Claude Notif.app/Contents/MacOS/ClaudeCode` without `timeout 3 ... &`.
2. The binary currently does NOT exit cleanly in CLI mode — `NSApplication.run()` blocks. Fix this before adding features.
3. After every Swift rebuild, test: `time "$HOME/Applications/Claude Notif.app/Contents/MacOS/ClaudeCode" --title T --message hi` must exit in <2s.
4. See SESSION_HANDOVER_2026-05-15.md for full context.
