import SwiftUI
import AppKit
import UserNotifications

// MARK: - Config

class NotifConfig: ObservableObject {
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/notifications.json")

    private struct Stored: Codable {
        var enabled: Bool        = true
        var soundDone:      String = "Ping"
        var soundError:     String = "Basso"
        var soundInterrupt: String = "Pop"
        var soundApproval:  String = "Funk"
        var enableDone:      Bool = true
        var enableError:     Bool = true
        var enableInterrupt: Bool = true
        var enableApproval:  Bool = true
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

    init() {
        let raw = try? Data(contentsOf: NotifConfig.fileURL)
        let s   = raw.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        enabled         = s.enabled
        soundDone       = s.soundDone
        soundError      = s.soundError
        soundInterrupt  = s.soundInterrupt
        soundApproval   = s.soundApproval
        enableDone      = s.enableDone
        enableError     = s.enableError
        enableInterrupt = s.enableInterrupt
        enableApproval  = s.enableApproval
    }

    func save() {
        let s = Stored(
            enabled: enabled,
            soundDone: soundDone, soundError: soundError,
            soundInterrupt: soundInterrupt, soundApproval: soundApproval,
            enableDone: enableDone, enableError: enableError,
            enableInterrupt: enableInterrupt, enableApproval: enableApproval
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

class AppDelegate: NSObject, NSApplicationDelegate {
    let config = NotifConfig()
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = CommandLine.arguments
        if args.contains("--title") || args.contains("--message") {
            sendNotification(args: args)
        } else {
            setupMenuBar()
            showSettingsWindow()
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
            content.title = title
            if !subtitle.isEmpty { content.subtitle = subtitle }
            content.body  = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            let icon = NSApp.applicationIconImage.copy() as! NSImage
            icon.size = NSSize(width: 18, height: 18)
            btn.image = icon
            btn.action = #selector(menuBarClicked)
            btn.target = self
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask:   [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        win.title = "Claude Notif"
        win.titlebarAppearsTransparent = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = NSHostingView(rootView: SettingsView(config: config))
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClaudeNotifSettings")
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

    var body: some View {
        ZStack {
            VisualEffect().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Claude Notification")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $config.enabled)
                        .toggleStyle(.switch)
                        .tint(brandColor)
                        .onChange(of: config.enabled) { config.save() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if config.enabled {
                    VStack(spacing: 0) {
                        SoundRow(label: "Done",       sound: $config.soundDone,      rowEnabled: $config.enableDone,      config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Error",      sound: $config.soundError,     rowEnabled: $config.enableError,     config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Interrupted",sound: $config.soundInterrupt, rowEnabled: $config.enableInterrupt, config: config)
                        Divider().padding(.leading, 16)
                        SoundRow(label: "Approval",   sound: $config.soundApproval,  rowEnabled: $config.enableApproval,  config: config)
                    }

                    Divider()

                    Button { sendTest() } label: {
                        Label("Test Notification", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brandColor)
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
        .frame(width: 320)
    }

    private func sendTest() {
        let center  = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Claude Code — Test"
        content.body  = "Notifications are working."
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content, trigger: nil))
        playSound(config.soundDone)
    }
}

// MARK: - Sound Row

struct SoundRow: View {
    let label:      String
    @Binding var sound:      String
    @Binding var rowEnabled: Bool
    let config:     NotifConfig

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(rowEnabled ? .secondary : .tertiary)
                .frame(width: 82, alignment: .leading)

            Picker("", selection: $sound) {
                ForEach(kSounds, id: \.self) { s in Text(s).tag(s) }
                Divider()
                if !kSounds.contains(sound) {
                    Text(URL(fileURLWithPath: sound).lastPathComponent).tag(sound)
                }
                Text("Custom file…").tag("__custom__")
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(!rowEnabled)
            .opacity(rowEnabled ? 1 : 0.35)
            .onChange(of: sound) { _, val in
                if val == "__custom__" { pickFile() } else { config.save() }
            }

            Button { playSound(sound) } label: {
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
                .onChange(of: rowEnabled) { config.save() }
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
            config.save()
        } else {
            sound = "Ping"
        }
    }
}

// MARK: - Helpers

private func playSound(_ sound: String) {
    let path = sound.hasPrefix("/") ? sound : "/System/Library/Sounds/\(sound).aiff"
    NSSound(contentsOfFile: path, byReference: false)?.play()
}
