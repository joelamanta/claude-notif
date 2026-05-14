# claude-notif

Native macOS notifications for [Claude Code](https://claude.ai/code) — plays a sound and shows a banner when Claude finishes responding.

![Claude Notif settings window](https://raw.githubusercontent.com/teevoteam/claude-notif/main/assets/screenshot.png)

## Install

```bash
npx claude-notif
```

That's it. Takes ~20 seconds to compile and install.

## What it does

- Plays a sound and shows a macOS notification banner every time Claude finishes a response
- Shows the session name and a preview of Claude's last message
- Different sounds for **Done**, **Error**, and **Interrupted** states
- Settings window to toggle on/off and pick sounds — open it any time with `open ~/Applications/Claude\ Notif.app`

## Requirements

- macOS 12 (Monterey) or later
- [Claude Code](https://claude.ai/code)
- Xcode Command Line Tools → `xcode-select --install`
- jq → `brew install jq`

## Settings

Open the settings window:

```bash
open ~/Applications/Claude\ Notif.app
```

Or find **Claude Notif** in Spotlight (`Cmd+Space`).

From there you can:
- Enable / disable notifications
- Pick sounds for Done, Error, and Interrupted events
- Use a custom sound file (any `.aiff`, `.wav`, `.mp3`, `.m4a`)
- Send a test notification

Settings are saved to `~/.claude/notifications.json`.

## Notification types

| Event | Default sound | When it fires |
|---|---|---|
| Done | Ping | Claude finishes a turn normally |
| Error | Basso | Response ends with an error |
| Interrupted | Pop | Session cancelled or paused |

## What gets installed

```
~/Applications/Claude Notif.app          ← settings UI + notification sender
~/.claude/hooks/claude-notif-stop.sh     ← fires on every Claude response
~/.claude/hooks/claude-notif-pre-tool-use.sh  ← tracks current tool for context
~/.claude/notifications.json             ← your settings (created if missing)
```

Two entries are added to `~/.claude/settings.json` — existing hooks are not touched.

## Custom sounds

Drop a sound file anywhere, then open the app → click the picker for any event → choose **"Custom file…"**

Supported formats: `.aiff`, `.wav`, `.mp3`, `.m4a`

## Uninstall

```bash
npx claude-notif uninstall
```

Removes the app, hook scripts, and hook entries from `settings.json`. Optionally removes your config.

## How it works

Claude Code runs the `stop.sh` hook at the end of every response. The hook:
1. Reads the session transcript to extract the AI-generated session title and last message
2. Plays the configured sound via `afplay`
3. Calls `Claude Notif.app` with `--title` and `--message` args, which fires a `UNUserNotificationCenter` banner

The app runs in two modes:
- **Notification mode** — when called with `--title`/`--message`, sends the notification and exits
- **Settings mode** — when opened normally, shows the settings window and sits in the menu bar

## Building from source

```bash
git clone https://github.com/teevoteam/claude-notif
cd claude-notif
bash scripts/install.sh
```

## License

MIT
