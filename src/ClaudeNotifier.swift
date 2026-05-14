import SwiftUI
import AppKit
import UserNotifications

// MARK: - Config

class NotifConfig: ObservableObject {
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/notifications.json")

    private struct Stored: Codable {
        var enabled: Bool        = true
        var soundDone:         String = "Ping"
        var soundError:        String = "Basso"
        var soundInterrupt:    String = "Pop"
        var soundApproval:     String = "Funk"
        var soundLongRunning:  String = "Glass"
        var enableDone:         Bool = true
        var enableError:        Bool = true
        var enableInterrupt:    Bool = true
        var enableApproval:     Bool = true
        var enableLongRunning:  Bool = false
        var volumeDone:         Double = 1.0
        var volumeError:        Double = 1.0
        var volumeInterrupt:    Double = 1.0
        var volumeApproval:     Double = 1.0
        var volumeLongRunning:  Double = 1.0
        var longRunningMinutes:     Int    = 10
        var longRunningThresholds:  [Int]? = nil
        var quietEnabled:           Bool   = false
        var quietFrom:          String = "22:00"
        var quietTo:            String = "08:00"
        var titlePrefix:        String = "Claude Code"
        var previewLength:      String = "sentence"
    }

    @Published var enabled: Bool
    @Published var soundDone: String
    @Published var soundError: String
    @Published var soundInterrupt: String
    @Published var soundApproval: String
    @Published var enableDone: Bool
    @Published var enableError: Bool
    @Published var enableInterrupt: Bool
    @Published var enableApproval: Bool
    @Published var enableLongRunning: Bool
    @Published var volumeDone: Double
    @Published var volumeError: Double
    @Published var volumeInterrupt: Double
    @Published var volumeApproval: Double
    @Published var volumeLongRunning: Double
    @Published var soundLongRunning: String
    @Published var longRunningThresholds: [Int]
    @Published var quietEnabled: Bool
    @Published var quietFrom: String
    @Published var quietTo: String
    @Published var titlePrefix: String
    @Published var previewLength: String

    init() {
        let raw = try? Data(contentsOf: NotifConfig.fileURL)
        let s   = raw.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        enabled         = s.enabled
        soundDone       = s.soundDone
        soundError      = s.soundError
        soundInterrupt  = s.soundInterrupt
        soundApproval   = s.soundApproval
        enableDone         = s.enableDone
        enableError        = s.enableError
        enableInterrupt    = s.enableInterrupt
        enableApproval     = s.enableApproval
        enableLongRunning  = s.enableLongRunning
        volumeDone         = s.volumeDone
        volumeError        = s.volumeError
        volumeInterrupt    = s.volumeInterrupt
        volumeApproval     = s.volumeApproval
        volumeLongRunning  = s.volumeLongRunning
        soundLongRunning   = s.soundLongRunning
        longRunningThresholds = s.longRunningThresholds ?? [s.longRunningMinutes]
        quietEnabled          = s.quietEnabled
        quietFrom          = s.quietFrom
        quietTo            = s.quietTo
        titlePrefix        = s.titlePrefix
        previewLength      = s.previewLength
    }

    func save() {
        let s = Stored(
            enabled: enabled,
            soundDone: soundDone, soundError: soundError,
            soundInterrupt: soundInterrupt, soundApproval: soundApproval,
            soundLongRunning: soundLongRunning,
            enableDone: enableDone, enableError: enableError,
            enableInterrupt: enableInterrupt, enableApproval: enableApproval,
            enableLongRunning: enableLongRunning,
            volumeDone: volumeDone, volumeError: volumeError,
            volumeInterrupt: volumeInterrupt, volumeApproval: volumeApproval,
            volumeLongRunning: volumeLongRunning,
            longRunningMinutes: longRunningThresholds.first ?? 10,
            longRunningThresholds: longRunningThresholds,
            quietEnabled: quietEnabled, quietFrom: quietFrom, quietTo: quietTo,
            titlePrefix: titlePrefix, previewLength: previewLength
        )
        try? JSONEncoder().encode(s).write(to: NotifConfig.fileURL)
    }
}

// MARK: - Visual Effect

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state        = .active
        v.material     = .sidebar
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let config = NotifConfig()
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let args = CommandLine.arguments
        if args.contains("--title") || args.contains("--message") {
            sendNotification(args: args)
        } else {
            setupMenuBar()
            showSettingsWindow()
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "OPEN_TERMINAL" {
            openTerminal()
        }
        completionHandler()
    }

    private func openTerminal() {
        let candidates = ["com.googlecode.iterm2", "dev.warp.desktop", "net.kovidgoyal.kitty",
                          "co.zeit.hyper", "com.apple.Terminal"]
        for bundleID in candidates {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               let url = app.bundleURL {
                NSWorkspace.shared.open(url)
                return
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    // MARK: Notification mode

    private func sendNotification(args: [String]) {
        NSApp.setActivationPolicy(.accessory)
        guard config.enabled else { NSApp.terminate(nil); return }

        var title = "Claude Code", subtitle = "", body = "Done."
        var i = 1
        while i < args.count {
            let v = i + 1 < args.count ? args[i + 1] : ""
            switch args[i] {
            case "--title":    title    = v; i += 2
            case "--subtitle": subtitle = v; i += 2
            case "--message":  body     = v; i += 2
            default:           i += 1
            }
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { DispatchQueue.main.async { NSApp.terminate(nil) }; return }
            let content = UNMutableNotificationContent()
            content.title              = title
            if !subtitle.isEmpty { content.subtitle = subtitle }
            content.body               = body
            content.categoryIdentifier = "CLAUDE_NOTIF"
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        let openAction = UNNotificationAction(identifier: "OPEN_TERMINAL", title: "Open Terminal", options: [.foreground])
        let category = UNNotificationCategory(identifier: "CLAUDE_NOTIF", actions: [openAction],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            let icon = NSApp.applicationIconImage.copy() as! NSImage
            icon.size = NSSize(width: 18, height: 18)
            btn.image = icon
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Enable Notifications", action: #selector(quickToggle), keyEquivalent: "")
        toggleItem.state = config.enabled ? .on : .off
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuBarClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Claude Notif", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // Menu bar quick toggle saves immediately — it's outside the settings window
    @objc private func quickToggle() {
        config.enabled.toggle()
        config.save()
        if let item = statusItem?.menu?.item(at: 0) {
            item.state = config.enabled ? .on : .off
        }
    }

    @objc private func menuBarClicked() {
        showSettingsWindow()
    }

    // MARK: Settings window

    func showSettingsWindow() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask:   [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        win.title = "Claude Notif"
        win.titlebarAppearsTransparent = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = NSHostingView(rootView: SettingsView(config: config, onPinToggle: { [weak win] pinned in
            win?.level = pinned ? .floating : .normal
        }))
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClaudeNotifSettings4")
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }
}

// MARK: - Entry Point

@main
struct ClaudeNotifEntry {
    static func main() {
        let app      = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Settings View

private let brandColor = Color(red: 0.58, green: 0.18, blue: 0.18)

private let kSounds = ["Ping", "Basso", "Pop", "Funk", "Glass", "Hero",
                       "Morse", "Bottle", "Frog", "Blow", "Purr", "Sosumi",
                       "Submarine", "Tink"]

struct SettingsView: View {
    @ObservedObject var config: NotifConfig
    @State private var saved = false
    @State private var isPinned = false
    var onPinToggle: (Bool) -> Void = { _ in }

    var body: some View {
        ZStack {
            VisualEffect().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Claude Notification")
                        .font(.headline)
                    Spacer()
                    Button {
                        isPinned.toggle()
                        onPinToggle(isPinned)
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 13))
                            .foregroundStyle(isPinned ? brandColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "Unpin window" : "Keep window on top")
                    .padding(.trailing, 4)
                    Toggle("", isOn: $config.enabled)
                        .toggleStyle(.switch)
                        .tint(brandColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if config.enabled {
                    VStack(spacing: 0) {
                        SoundRow(label: "Done",        sound: $config.soundDone,      volume: $config.volumeDone,      rowEnabled: $config.enableDone,      config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Error",       sound: $config.soundError,     volume: $config.volumeError,     rowEnabled: $config.enableError,     config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Interrupted", sound: $config.soundInterrupt, volume: $config.volumeInterrupt, rowEnabled: $config.enableInterrupt, config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Approval",    sound: $config.soundApproval,  volume: $config.volumeApproval,  rowEnabled: $config.enableApproval,  config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Long run",    sound: $config.soundLongRunning, volume: $config.volumeLongRunning, rowEnabled: $config.enableLongRunning, config: config)
                        Divider().padding(.leading, 16)
                        ForEach(config.longRunningThresholds.indices, id: \.self) { idx in
                            if idx > 0 { Divider().padding(.leading, 16) }
                            HStack(spacing: 8) {
                                Text(idx == 0 ? "Alert after" : "")
                                    .foregroundStyle(config.enableLongRunning ? .secondary : .tertiary)
                                    .frame(width: 78, alignment: .leading)
                                LongRunPicker(value: Binding(
                                    get: { config.longRunningThresholds[idx] },
                                    set: { config.longRunningThresholds[idx] = $0 }
                                ), disabled: !config.enableLongRunning)
                                Spacer()
                                if config.longRunningThresholds.count > 1 {
                                    Button { config.longRunningThresholds.remove(at: idx) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(config.enableLongRunning ? Color.secondary : Color.secondary.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!config.enableLongRunning)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        if config.longRunningThresholds.count < 5 {
                            Divider().padding(.leading, 16)
                            HStack(spacing: 8) {
                                Spacer().frame(width: 78)
                                Button {
                                    let last = config.longRunningThresholds.max() ?? 10
                                    config.longRunningThresholds.append(last + 5)
                                } label: {
                                    Label("Add alert", systemImage: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(config.enableLongRunning ? brandColor : Color.secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .disabled(!config.enableLongRunning)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    Divider()

                    QuietHoursRow(config: config)

                    Divider()

                    // Title prefix
                    HStack(spacing: 8) {
                        Text("Title")
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        TextField("Claude Code", text: $config.titlePrefix)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // Preview length
                    HStack(spacing: 8) {
                        Text("Preview")
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Picker("", selection: $config.previewLength) {
                            Text("1 sentence").tag("sentence")
                            Text("2 sentences").tag("two")
                            Text("Full").tag("full")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    // Save + Test buttons
                    HStack(spacing: 8) {
                        Button {
                            config.save()
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                        } label: {
                            Text(saved ? "Saved ✓" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(saved ? .green : brandColor)

                        Button { sendTest() } label: {
                            Label("Test Notification", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(brandColor)
                    }
                    .padding(14)

                } else {
                    Text("Notifications are disabled.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                }

                Divider()

                Text("claude-notif v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")  ·  Developed by Teevo Joel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 440)
    }

    private func sendTest() {
        let prefix = config.titlePrefix.isEmpty ? "Claude Code" : config.titlePrefix
        let body: String
        switch config.previewLength {
        case "two":
            body = "Notifications are working. This is what a two-sentence preview looks like."
        case "full":
            body = "Notifications are working. This is what a full preview looks like. It shows more context from the response without truncating at the first sentence."
        default:
            body = "Notifications are working."
        }
        let center  = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title              = "\(prefix) — Test"
        content.subtitle           = "Just now"
        content.body               = body
        content.categoryIdentifier = "CLAUDE_NOTIF"
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content, trigger: nil))
        playSound(config.soundDone, volume: config.volumeDone)
    }
}

// MARK: - Quiet Hours Row

private let kTimes: [String] = (0..<24).flatMap { h in
    [0, 15, 30, 45].map { m in String(format: "%02d:%02d", h, m) }
}

struct TimePicker: View {
    @Binding var time: String
    let disabled: Bool

    private var normalized: String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let h = parts.count > 0 ? parts[0] : 0
        let m = parts.count > 1 ? (parts[1] / 15) * 15 : 0
        return String(format: "%02d:%02d", h, m)
    }

    var body: some View {
        Picker("", selection: Binding(
            get: { normalized },
            set: { time = $0 }
        )) {
            ForEach(kTimes, id: \.self) { t in Text(t).tag(t) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 110)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

struct QuietHoursRow: View {
    @ObservedObject var config: NotifConfig

    var body: some View {
        HStack(spacing: 8) {
            Text("Quiet hours")
                .foregroundStyle(config.quietEnabled ? .secondary : .tertiary)
                .frame(width: 78, alignment: .leading)

            TimePicker(time: $config.quietFrom, disabled: !config.quietEnabled)

            Text("to")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .padding(.horizontal, -4)

            TimePicker(time: $config.quietTo, disabled: !config.quietEnabled)

            Spacer()

            Toggle("", isOn: $config.quietEnabled)
                .toggleStyle(.switch)
                .tint(brandColor)
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Sound Row

struct SoundRow: View {
    let label:      String
    @Binding var sound:      String
    @Binding var volume:     Double
    @Binding var rowEnabled: Bool
    let config:     NotifConfig

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(rowEnabled ? .secondary : .tertiary)
                .frame(width: 78, alignment: .leading)

            Picker("", selection: $sound) {
                ForEach(kSounds, id: \.self) { s in Text(s).tag(s) }
                Divider()
                if !kSounds.contains(sound) {
                    Text(URL(fileURLWithPath: sound).lastPathComponent).tag(sound)
                }
                Text("Custom file…").tag("__custom__")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
            .disabled(!rowEnabled)
            .opacity(rowEnabled ? 1 : 0.35)
            .onChange(of: sound) { _, val in
                if val == "__custom__" { pickFile() }
            }

            Image(systemName: volume < 0.01 ? "speaker.slash.fill" : volume < 0.4 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(rowEnabled ? Color.secondary : Color.secondary.opacity(0.35))
                .frame(width: 14)

            Slider(value: $volume, in: 0...1)
                .frame(maxWidth: .infinity)
                .disabled(!rowEnabled)
                .opacity(rowEnabled ? 1 : 0.35)
                .tint(brandColor)

            Button { playSound(sound, volume: volume) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(rowEnabled ? brandColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!rowEnabled)

            Toggle("", isOn: $rowEnabled)
                .toggleStyle(.switch)
                .tint(brandColor)
                .labelsHidden()
                .scaleEffect(0.75)
                .frame(width: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound file (.aiff, .wav, .mp3, .m4a)"
        if panel.runModal() == .OK, let url = panel.url {
            sound = url.path
        } else {
            sound = "Ping"
        }
    }
}

// MARK: - Long Run Threshold Picker

struct LongRunPicker: View {
    @Binding var value: Int
    let disabled: Bool
    private let options = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    var body: some View {
        Picker("", selection: $value) {
            ForEach(options, id: \.self) { m in
                Text(m == 60 ? "1 hour" : "\(m) min").tag(m)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 110)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - Helpers

private func playSound(_ sound: String, volume: Double = 1.0) {
    let path = sound.hasPrefix("/") ? sound : "/System/Library/Sounds/\(sound).aiff"
    if let s = NSSound(contentsOfFile: path, byReference: false) {
        s.volume = Float(volume)
        s.play()
    }
}
