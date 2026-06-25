import SwiftUI
import AppKit
import UserNotifications

// MARK: - Config

enum NotifProfile: String, CaseIterable, Identifiable {
    case claude, cursor, codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .codex:  return "Codex"
        }
    }

    var defaultTitle: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex:  return "Codex"
        }
    }

    var openAppName: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .codex:  return "Codex"
        }
    }

    var queueFile: String {
        switch self {
        case .claude: return "/tmp/noto-claude-pending.json"
        case .cursor: return "/tmp/noto-cursor-pending.json"
        case .codex:  return "/tmp/noto-codex-pending.json"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: return Color(red: 0.86, green: 0.55, blue: 0.22)
        case .cursor: return Color(red: 0.32, green: 0.52, blue: 0.94)
        case .codex:  return Color(red: 0.30, green: 0.72, blue: 0.44)
        }
    }

    var hookScriptPath: String {
        let home = NSHomeDirectory()
        switch self {
        case .claude: return "\(home)/.claude/hooks/noto-stop.sh"
        case .cursor: return "\(home)/.cursor/hooks/after-agent-response.sh"
        case .codex:  return "\(home)/.codex/hooks/stop.sh"
        }
    }
}

enum NotifFocusMode: String, CaseIterable, Codable, Identifiable {
    case available, deepWork, away

    var id: String { rawValue }

    var label: String {
        switch self {
        case .available: return "Available"
        case .deepWork:  return "Deep Work"
        case .away:      return "Away"
        }
    }

    var help: String {
        switch self {
        case .available: return "Normal notifications for each profile"
        case .deepWork:  return "Done notifications only — blocks approval, errors, and long-run alerts"
        case .away:      return "All notification types enabled — use when away from your desk"
        }
    }
}

struct ProfileSettings: Codable, Equatable {
    var enabled: Bool = true
    var soundDone: String = "Ping"
    var soundError: String = "Basso"
    var soundInterrupt: String = "Pop"
    var soundApproval: String = "Funk"
    var soundLongRunning: String = "Glass"
    var enableDone: Bool = true
    var enableError: Bool = true
    var enableInterrupt: Bool = true
    var enableApproval: Bool = true
    var enableLongRunning: Bool = false
    var volumeDone: Double = 1.0
    var volumeError: Double = 1.0
    var volumeInterrupt: Double = 1.0
    var volumeApproval: Double = 1.0
    var volumeLongRunning: Double = 1.0
    var longRunningMinutes: Int = 10
    var longRunningThresholds: [Int]? = nil
    var quietEnabled: Bool = false
    var quietFrom: String = "22:00"
    var quietTo: String = "08:00"
    var titlePrefix: String = "Claude Code"
    var previewLength: String = "sentence"

    static func defaults(for profile: NotifProfile) -> ProfileSettings {
        var s = ProfileSettings()
        s.titlePrefix = profile.defaultTitle
        switch profile {
        case .claude:
            s.soundDone = "Ping"
        case .cursor:
            s.soundDone = "Purr"
            s.enableLongRunning = true
            s.longRunningThresholds = [3, 5, 10]
        case .codex:
            s.soundDone = "Hero"
            s.soundApproval = "Tink"
        }
        return s
    }

    var resolvedThresholds: [Int] {
        longRunningThresholds ?? [longRunningMinutes]
    }

    mutating func applyPreset(_ preset: NotifPreset, for profile: NotifProfile) {
        let keepEnabled = enabled
        let keepTitle = titlePrefix

        switch preset {
        case .standard:
            self = ProfileSettings.defaults(for: profile)
        case .focus:
            self = ProfileSettings.defaults(for: profile)
            previewLength = "sentence"
            volumeDone = 0.6
            enableError = false
            enableInterrupt = false
            enableApproval = false
            enableLongRunning = false
            quietEnabled = false
        case .loud:
            self = ProfileSettings.defaults(for: profile)
            previewLength = "two"
            enableDone = true
            enableError = true
            enableInterrupt = true
            enableApproval = true
            enableLongRunning = true
            soundDone = "Hero"
            soundError = "Basso"
            soundInterrupt = "Sosumi"
            soundApproval = "Funk"
            soundLongRunning = "Glass"
            volumeDone = 1.0
            volumeError = 1.0
            volumeInterrupt = 1.0
            volumeApproval = 1.0
            volumeLongRunning = 1.0
            if profile == .cursor {
                longRunningThresholds = [3, 5, 10, 15]
            } else {
                longRunningThresholds = [5, 10, 15]
            }
        }

        enabled = keepEnabled
        titlePrefix = keepTitle
    }

    static func plainTextForNotch(_ text: String) -> String {
        var parts: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.range(of: #"^\|?[\s\-:|]+\|?$"#, options: .regularExpression) != nil { continue }
            if line.hasPrefix("#") {
                line = line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            }
            line = line.replacingOccurrences(of: #"^[\-*•]\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "|", with: " ")
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "__", with: "")
            line = line.replacingOccurrences(of: "`", with: "")
            line = line.replacingOccurrences(of: #"  +"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            parts.append(line)
        }
        let joined = parts.joined(separator: " ")
        return joined.replacingOccurrences(of: #"  +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func previewText(from text: String, mode: String) -> String {
        let trimmed = plainTextForNotch(text)
        guard !trimmed.isEmpty else { return "Done." }

        let sentences = splitSentences(trimmed)
        switch mode {
        case "two":
            if sentences.count >= 2 {
                return "\(sentences[0]) \(sentences[1])"
            }
            if let first = sentences.first {
                return first
            }
            return clipForDisplay(String(trimmed.prefix(160)), maxCharacters: 160)
        case "full":
            return clipForDisplay(String(trimmed.prefix(200)), maxCharacters: 200)
        default:
            if let first = sentences.first {
                return first
            }
            return clipForDisplay(String(trimmed.prefix(80)), maxCharacters: 80)
        }
    }

    /// Notch preview: up to two sentences, clipped at word boundaries — never ends with "..."
    static func notchBodyText(from text: String) -> String {
        clipForDisplay(previewText(from: text, mode: "two"), maxCharacters: 108)
    }

    static func notchTitleText(_ text: String) -> String {
        let plain = plainTextForNotch(text)
        return clipForDisplay(plain.isEmpty ? text : plain, maxCharacters: 44)
    }

    static func notchMetaText(_ text: String) -> String {
        clipForDisplay(text, maxCharacters: 36)
    }

    static func clipForDisplay(_ text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        var slice = String(trimmed[..<end])
        if let lastSpace = slice.lastIndex(of: " ") {
            slice = String(slice[..<lastSpace])
        }
        return slice.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitSentences(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?<=[.!?])\\s+") else {
            return [text]
        }

        let nsText = text as NSString
        var sentences: [String] = []
        var start = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let end = match.range.location + match.range.length
            let chunk = nsText.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                sentences.append(chunk)
            }
            start = end
        }

        let tail = nsText.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }

        return sentences.isEmpty ? [text] : sentences
    }

    static func previewBodyLikeHook(from text: String, mode: String) -> String {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.cursor/hooks/preview-text.py",
            "\(home)/.claude/hooks/preview-text.py",
            "\(home)/.codex/hooks/preview-text.py",
        ]

        guard let script = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return previewText(from: text, mode: mode)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script, mode]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            if let data = text.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !output.isEmpty {
                return output
            }
        } catch {}

        return previewText(from: text, mode: mode)
    }
}

class NotifConfig: ObservableObject {
    static let fileURL = resolveConfigURL()

    enum SaveState: Equatable {
        case saved
        case saving
    }

    @Published private(set) var saveState: SaveState = .saved
    private var saveWorkItem: DispatchWorkItem?

    private static func resolveConfigURL() -> URL {
        let home = NSHomeDirectory()
        let newURL = URL(fileURLWithPath: home + "/.noto/notifications.json")
        let oldURL = URL(fileURLWithPath: home + "/.claude/notifications.json")
        let fm = FileManager.default
        if !fm.fileExists(atPath: newURL.path) {
            try? fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: oldURL.path) {
                try? fm.copyItem(at: oldURL, to: newURL)
            }
        }
        return newURL
    }

    private struct Stored: Codable {
        var enabled: Bool = true
        var focusMode: NotifFocusMode?
        var respectMacFocus: Bool?
        var notchPreviewEnabled: Bool?
        var claude: ProfileSettings?
        var cursor: ProfileSettings?
        var codex: ProfileSettings?
        // Legacy flat keys — decoded for migration only
        var soundDone: String?
        var soundError: String?
        var soundInterrupt: String?
        var soundApproval: String?
        var soundLongRunning: String?
        var enableDone: Bool?
        var enableError: Bool?
        var enableInterrupt: Bool?
        var enableApproval: Bool?
        var enableLongRunning: Bool?
        var volumeDone: Double?
        var volumeError: Double?
        var volumeInterrupt: Double?
        var volumeApproval: Double?
        var volumeLongRunning: Double?
        var longRunningMinutes: Int?
        var longRunningThresholds: [Int]?
        var quietEnabled: Bool?
        var quietFrom: String?
        var quietTo: String?
        var titlePrefix: String?
        var previewLength: String?
    }

    @Published var enabled: Bool
    @Published var focusMode: NotifFocusMode
    @Published var respectMacFocus: Bool
    @Published var notchPreviewEnabled: Bool
    @Published var claude: ProfileSettings
    @Published var cursor: ProfileSettings
    @Published var codex: ProfileSettings

    init() {
        let raw = try? Data(contentsOf: NotifConfig.fileURL)
        let s = raw.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        enabled = s.enabled
        focusMode = s.focusMode ?? .available
        respectMacFocus = s.respectMacFocus ?? true
        notchPreviewEnabled = s.notchPreviewEnabled ?? true

        if s.claude != nil || s.cursor != nil || s.codex != nil {
            claude = s.claude ?? ProfileSettings.defaults(for: .claude)
            cursor = s.cursor ?? ProfileSettings.defaults(for: .cursor)
            codex  = s.codex  ?? ProfileSettings.defaults(for: .codex)
        } else {
            var legacy = ProfileSettings.defaults(for: .cursor)
            if let v = s.soundDone         { legacy.soundDone = v }
            if let v = s.soundError        { legacy.soundError = v }
            if let v = s.soundInterrupt    { legacy.soundInterrupt = v }
            if let v = s.soundApproval    { legacy.soundApproval = v }
            if let v = s.soundLongRunning { legacy.soundLongRunning = v }
            if let v = s.enableDone         { legacy.enableDone = v }
            if let v = s.enableError        { legacy.enableError = v }
            if let v = s.enableInterrupt    { legacy.enableInterrupt = v }
            if let v = s.enableApproval    { legacy.enableApproval = v }
            if let v = s.enableLongRunning  { legacy.enableLongRunning = v }
            if let v = s.volumeDone         { legacy.volumeDone = v }
            if let v = s.volumeError        { legacy.volumeError = v }
            if let v = s.volumeInterrupt    { legacy.volumeInterrupt = v }
            if let v = s.volumeApproval     { legacy.volumeApproval = v }
            if let v = s.volumeLongRunning  { legacy.volumeLongRunning = v }
            if let v = s.longRunningMinutes     { legacy.longRunningMinutes = v }
            if let v = s.longRunningThresholds  { legacy.longRunningThresholds = v }
            if let v = s.quietEnabled       { legacy.quietEnabled = v }
            if let v = s.quietFrom          { legacy.quietFrom = v }
            if let v = s.quietTo            { legacy.quietTo = v }
            if let v = s.titlePrefix        { legacy.titlePrefix = v }
            if let v = s.previewLength      { legacy.previewLength = v }

            let target: NotifProfile
            switch legacy.titlePrefix.lowercased() {
            case "claude code", "claude": target = .claude
            case "codex": target = .codex
            default: target = .cursor
            }

            claude = ProfileSettings.defaults(for: .claude)
            cursor = ProfileSettings.defaults(for: .cursor)
            codex  = ProfileSettings.defaults(for: .codex)
            switch target {
            case .claude: claude = legacy
            case .cursor: cursor = legacy
            case .codex:  codex  = legacy
            }
        }
    }

    func settings(for profile: NotifProfile) -> ProfileSettings {
        switch profile {
        case .claude: return claude
        case .cursor: return cursor
        case .codex:  return codex
        }
    }

    func update(_ profile: NotifProfile, with settings: ProfileSettings) {
        switch profile {
        case .claude: claude = settings
        case .cursor: cursor = settings
        case .codex:  codex  = settings
        }
    }

    func binding(for profile: NotifProfile) -> Binding<ProfileSettings> {
        Binding(
            get: { self.settings(for: profile) },
            set: { self.update(profile, with: $0) }
        )
    }

    func save() {
        let s = Stored(
            enabled: enabled,
            focusMode: focusMode,
            respectMacFocus: respectMacFocus,
            notchPreviewEnabled: notchPreviewEnabled,
            claude: claude,
            cursor: cursor,
            codex: codex
        )
        let dir = NotifConfig.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: NotifConfig.fileURL, options: .atomic)
        reloadFromDisk()
        saveState = .saved
    }

    func scheduleAutoSave() {
        saveWorkItem?.cancel()
        saveState = .saving
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func reloadFromDisk() {
        guard let raw = try? Data(contentsOf: NotifConfig.fileURL),
              let s = try? JSONDecoder().decode(Stored.self, from: raw)
        else { return }

        enabled = s.enabled
        focusMode = s.focusMode ?? .available
        respectMacFocus = s.respectMacFocus ?? true
        notchPreviewEnabled = s.notchPreviewEnabled ?? true
        claude = s.claude ?? ProfileSettings.defaults(for: .claude)
        cursor = s.cursor ?? ProfileSettings.defaults(for: .cursor)
        codex  = s.codex  ?? ProfileSettings.defaults(for: .codex)
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

// MARK: - Notification Delivery

struct PendingNotification {
    let profile: NotifProfile
    let title: String
    let subtitle: String
    let body: String
    let sound: String
    let volume: Double
    let openApp: String
    let kind: String

    init?(_ json: [String: String]) {
        let profileKey = json["profile"] ?? "cursor"
        profile = NotifProfile(rawValue: profileKey) ?? .cursor
        title = json["title"] ?? ""
        subtitle = json["subtitle"] ?? ""
        body = json["body"] ?? "Done."
        sound = json["sound"] ?? ""
        volume = Double(json["volume"] ?? "1.0") ?? 1.0
        openApp = json["openApp"] ?? profile.openAppName
        kind = json["kind"] ?? "done"
    }

    init(profile: NotifProfile, title: String, subtitle: String, body: String,
         sound: String, volume: Double, openApp: String, kind: String) {
        self.profile = profile
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.sound = sound
        self.volume = volume
        self.openApp = openApp
        self.kind = kind
    }
}

enum NotoSnooze {
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory() + "/.noto/snooze-until")

    static func isActive() -> Bool {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8),
              let until = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return Int(Date().timeIntervalSince1970) < until
    }

    static func untilDate() -> Date? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8),
              let until = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(until))
        return date > Date() ? date : nil
    }

    static func set(minutes: Int) {
        let until = Int(Date().timeIntervalSince1970) + minutes * 60
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(until).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum MacFocusMonitor {
    static let stateFileURL = URL(fileURLWithPath: NSHomeDirectory() + "/.noto/mac-focus-active")
    private static var pollTimer: Timer?

    static func startPolling() {
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            refresh()
        }

        let center = DistributedNotificationCenter.default()
        for name in [
            "com.apple.notificationcenterui.dndStart",
            "com.apple.notificationcenterui.dndEnd",
            "com.apple.focus.status",
        ] {
            center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in
                refresh()
            }
        }
    }

    static func refresh() {
        let active = detectActive()
        let dir = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? (active ? "1" : "0").write(to: stateFileURL, atomically: true, encoding: .utf8)
    }

    static func isActive() -> Bool {
        if let raw = try? String(contentsOf: stateFileURL, encoding: .utf8) {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }
        return detectActive()
    }

    private static func detectActive() -> Bool {
        let domain = "com.apple.notificationcenterui" as CFString
        for key in ["DoNotDisturb", "dndEnabled"] {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                if (value as? Bool) == true { return true }
                if (value as? Int) == 1 { return true }
            }
        }
        return false
    }
}

struct NotoEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var timestamp: TimeInterval
    var profile: String
    var kind: String
    var title: String
    var subtitle: String
    var body: String
    var sound: String = ""
    var delivered: Bool
    var suppressReason: String?
    var openApp: String?

    var date: Date { Date(timeIntervalSince1970: timestamp) }

    var menuHeadline: String {
        title.isEmpty ? body : title
    }

    var menuDetail: String {
        if !subtitle.isEmpty { return subtitle }
        if !title.isEmpty && !body.isEmpty { return body }
        return body
    }

    func display(profileHint: NotifProfile? = nil) -> NotoNotificationDisplay {
        NotoNotificationDisplay(event: self, profileHint: profileHint)
    }
}

struct NotoNotificationDisplay: Equatable {
    let profile: NotifProfile
    let title: String
    let subtitle: String
    let body: String
    let sound: String?

    init(profile: NotifProfile, title: String, subtitle: String, body: String, sound: String?) {
        self.profile = profile
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.sound = sound
    }

    init(event: NotoEvent, profileHint: NotifProfile? = nil) {
        profile = profileHint
            ?? NotifProfile.allCases.first(where: { $0.label == event.profile })
            ?? .cursor
        title = event.title.isEmpty ? profile.defaultTitle : event.title
        subtitle = event.subtitle
        body = event.body.isEmpty ? "Done." : event.body
        sound = event.sound.isEmpty ? nil : event.sound
    }

    static func preview(for profile: NotifProfile, settings: ProfileSettings) -> NotoNotificationDisplay {
        NotoNotificationDisplay(
            profile: profile,
            title: settings.titlePrefix.isEmpty ? profile.defaultTitle : settings.titlePrefix,
            subtitle: sampleSubtitle(for: profile),
            body: ProfileSettings.previewText(from: kPreviewSample, mode: settings.previewLength),
            sound: settings.soundDone
        )
    }

    static func sampleSubtitle(for profile: NotifProfile) -> String {
        switch profile {
        case .cursor: return "Your Project · 2m 14s"
        case .claude: return "2m 14s"
        case .codex:  return ""
        }
    }

    var notchTitle: String { ProfileSettings.notchTitleText(title) }
    var notchBody: String { ProfileSettings.notchBodyText(from: body) }
    var notchMeta: String { ProfileSettings.notchMetaText(subtitle) }
}

enum NotoEventLog {
    static let fileURL = URL(fileURLWithPath: NSHomeDirectory() + "/.noto/events.json")
    static let maxEvents = 40
    static let menuLimit = 8

    static func load() -> [NotoEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([NotoEvent].self, from: data)
        else { return [] }
        return events
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    static func record(_ item: PendingNotification, delivered: Bool, resolvedTitle: String? = nil, reason: String? = nil) {
        var events = load()
        let title = resolvedTitle ?? item.title
        events.insert(
            NotoEvent(
                id: UUID(),
                timestamp: Date().timeIntervalSince1970,
                profile: item.profile.label,
                kind: item.kind,
                title: title,
                subtitle: item.subtitle,
                body: item.body,
                sound: item.sound,
                delivered: delivered,
                suppressReason: reason,
                openApp: item.openApp
            ),
            at: 0
        )
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
        persist(events)
    }

    private static func persist(_ events: [NotoEvent]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Design System

private enum NotoDesign {
    static let brand = Color(red: 0.58, green: 0.18, blue: 0.18)

    static let settingsWidth: CGFloat = 440
    static let settingsHeight: CGFloat = 880
    static let headerHeight: CGFloat = 56
    static let platformBarHeight: CGFloat = 108
    static let tabsHeight: CGFloat = 48
    static let previewHeight: CGFloat = 124
    static let saveStatusHeight: CGFloat = 28
    static let actionBarHeight: CGFloat = 52
    static let hookHealthHeight: CGFloat = 34
    static let footerHeight: CGFloat = 34
    static let labelWidth: CGFloat = 78
    static let pickerWidth: CGFloat = 110

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 20
    }

    /// App-wide layout grid for the notch UI. Use only these tokens for padding and gaps.
    enum Layout {
        /// Outer shell margin — equal on all four sides of every page.
        static let margin = Space.lg
        /// Inner padding for grouped surfaces, toolbars, and list rows.
        static let inset = Space.md
        /// Compact vertical padding inside dense rows.
        static let insetTight = Space.sm
        /// Standard gap between related controls in a row.
        static let gap = Space.sm
        /// Tight gap between icons in a toolbar group.
        static let gapTight = Space.xs
        /// Gap between major sections on a page.
        static let sectionGap = Space.md
        /// Shared control heights.
        static let toolbarHeight: CGFloat = 36
        static let rowHeight: CGFloat = 28
        static let bannerHeight: CGFloat = 32
        static let dividerHeight: CGFloat = Space.md
    }

    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
        static let chip: CGFloat = 8
        static let action: CGFloat = 8
        static let tab: CGFloat = 8
        static let notch: CGFloat = 18
        static let pill: CGFloat = 14
    }

    enum NotchOpacity {
        static let body: Double = 0.88
        static let secondary: Double = 0.68
        static let meta: Double = 0.52
        static let tertiary: Double = 0.42
        static let quaternary: Double = 0.30
        static let label: Double = 0.38
        static let tabInactive: Double = 0.48
        static let interactive: Double = 0.82
        static let surfaceSubtle: Double = 0.05
        static let surfaceMuted: Double = 0.10
        static let surfaceEmphasis: Double = 0.14
        static let separator: Double = 0.12
    }

    enum NotchColor {
        static let surface = Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.98)
        static let surfaceElevated = Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.98)
        static let stroke = Color.primary.opacity(0.09)
        /// Matches grouped Form rows in Settings (dark mode control background).
        static let fillGrouped = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    enum NotchAccent {
        static let done = Color(nsColor: .systemGreen)
        static let hub = Color(nsColor: .systemBlue)
        static let roll = Color(nsColor: .systemOrange)
    }

    enum NotchLayout {
        static let pageBarHeight: CGFloat = Layout.toolbarHeight
        static let headerHeight: CGFloat = 24
        static let alertsContentHeight: CGFloat = 88
        static let alertsCardPadding: CGFloat = Layout.inset
        static let todoMetaHeight: CGFloat = 24
        static let todoRowHeight: CGFloat = Layout.rowHeight
        static let rowGap: CGFloat = 0
        static let sectionHeaderGap: CGFloat = Layout.gapTight
        static let todoEmptyListHeight: CGFloat = 28
        static let todoAddHeight: CGFloat = Layout.toolbarHeight
        static let buttonHeight: CGFloat = 32
        static let sectionGap: CGFloat = Layout.sectionGap
        static let interSectionGap: CGFloat = Layout.gap
        static let margin = Layout.margin
        static let inset = Layout.inset
        static let padH = Layout.margin
        static let padTop = Layout.margin
        static let padBottom = Layout.margin
        static let padInner = Layout.inset
        static let padRowH = Layout.inset
        static let alertsBodyHeight: CGFloat =
            headerHeight + Layout.gap + alertsContentHeight

        static let todoSectionHeaderHeight: CGFloat = 22
        static let todoBannerHeight: CGFloat = Layout.bannerHeight
        static let todoRowInnerSpacing: CGFloat = Layout.gap
        static let notesRowTitleGap: CGFloat = Layout.gapTight
        static let actionRadius = Radius.action
        static let todoFloatingHeaderHeight: CGFloat = 28
        static let doneOverflowHeight: CGFloat = 16

        static func todoListHeight(metrics: NotchTodoLayoutMetrics, doneExpanded: Bool) -> CGFloat {
            if metrics.nowCount == 0 && metrics.todayCount == 0 && metrics.doneCount == 0 {
                return todoEmptyListHeight
            }
            var h = CGFloat(metrics.visibleRowCount) * todoRowHeight
            let rowDividers = max(0, metrics.visibleRowCount - 1)
            let sectionDividers = max(0, metrics.sectionCount - 1)
            h += CGFloat(rowDividers + sectionDividers) * notesPanelDivider
            h += CGFloat(metrics.sectionCount) * (todoSectionHeaderHeight + Layout.gap)
            if metrics.rolledBanner { h += todoBannerHeight + Layout.gap }
            if metrics.hiddenHubBanner { h += todoBannerHeight + Layout.gap }
            if metrics.doneCount > 2 && !doneExpanded { h += doneOverflowHeight + notesPanelDivider }
            return h
        }

        static func todoListHeight(itemCount: Int) -> CGFloat {
            guard itemCount > 0 else { return todoEmptyListHeight }
            return CGFloat(itemCount) * todoRowHeight
                + CGFloat(itemCount - 1) * rowGap
        }

        static func todoBodyHeight(metrics: NotchTodoLayoutMetrics, doneExpanded: Bool) -> CGFloat {
            todoMetaHeight + sectionGap + todoListHeight(metrics: metrics, doneExpanded: doneExpanded)
                + sectionGap + todoAddHeight
        }

        static func todoPreviewBodyHeight(metrics: NotchTodoLayoutMetrics, doneExpanded: Bool) -> CGFloat {
            todoMetaHeight + sectionGap + todoListHeight(metrics: metrics, doneExpanded: doneExpanded)
        }

        static func todoFloatingHeight(metrics: NotchTodoLayoutMetrics, doneExpanded: Bool) -> CGFloat {
            padTop + todoFloatingHeaderHeight + sectionGap + todoPreviewBodyHeight(metrics: metrics, doneExpanded: doneExpanded) + padBottom
        }

        static let notesTopActionsHeight: CGFloat = Layout.toolbarHeight
        static let notesEditorHeight: CGFloat = 72
        static let notesFloatingEditorHeight: CGFloat = 200
        static let notesFormatBarHeight: CGFloat = Layout.toolbarHeight
        static let notesBrowseSearchHeight: CGFloat = 40
        static let notesBrowseRowHeight: CGFloat = 48
        static let notesPanelDivider: CGFloat = 1
        static let notesFloatingWidth: CGFloat = 420

        static func notesBrowseHeight(metrics: NotchNotesLayoutMetrics) -> CGFloat {
            guard metrics.browseExpanded else { return 0 }
            let rows = CGFloat(metrics.browseRowCount)
            var h = notesBrowseSearchHeight
            if rows > 0 {
                h += rows * notesBrowseRowHeight
                if rows > 1 {
                    h += (rows - 1) * notesPanelDivider
                }
            }
            return h
        }

        static func notesBodyHeight(metrics: NotchNotesLayoutMetrics, floating: Bool) -> CGFloat {
            var h = notesTopActionsHeight + notesPanelDivider
            if metrics.browseExpanded {
                h += notesBrowseHeight(metrics: metrics)
            } else {
                h += floating ? notesFloatingEditorHeight : notesEditorHeight
            }
            h += notesPanelDivider + notesFormatBarHeight
            return h
        }

        static func notesFloatingHeight(metrics: NotchNotesLayoutMetrics) -> CGFloat {
            padTop + notesBodyHeight(metrics: metrics, floating: true) + padBottom
        }

        static func pageBodyHeight(
            page: NotchPage,
            todoMetrics: NotchTodoLayoutMetrics,
            todoDoneExpanded: Bool,
            notesMetrics: NotchNotesLayoutMetrics,
            isTodoPreview: Bool,
            isNotesPreview: Bool
        ) -> CGFloat {
            switch page {
            case .notifications:
                return alertsBodyHeight
            case .todo:
                return isTodoPreview
                    ? todoPreviewBodyHeight(metrics: todoMetrics, doneExpanded: todoDoneExpanded)
                    : todoBodyHeight(metrics: todoMetrics, doneExpanded: todoDoneExpanded)
            case .notes:
                return notesBodyHeight(metrics: notesMetrics, floating: isNotesPreview)
            }
        }

        static func expandedContentHeight(
            page: NotchPage,
            todoMetrics: NotchTodoLayoutMetrics,
            todoDoneExpanded: Bool,
            notesMetrics: NotchNotesLayoutMetrics,
            showsFooter: Bool,
            isTodoPreview: Bool = false,
            isNotesPreview: Bool = false
        ) -> CGFloat {
            let body = pageBodyHeight(
                page: page,
                todoMetrics: todoMetrics,
                todoDoneExpanded: todoDoneExpanded,
                notesMetrics: notesMetrics,
                isTodoPreview: isTodoPreview,
                isNotesPreview: isNotesPreview
            )
            let base = padTop + pageBarHeight + sectionGap + body + padBottom
            if showsFooter {
                return base + sectionGap + buttonHeight
            }
            return base
        }
    }

    enum NotchPalette {
        static let surface = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.98)
        static let surfaceHighlight = NSColor.white.withAlphaComponent(0.04)
        static let stroke = NSColor.white.withAlphaComponent(0.11)
        static let grabber = NSColor.white.withAlphaComponent(0.22)
    }

    enum Surface {
        static let fill = Color.primary.opacity(0.045)
        static let stroke = Color.primary.opacity(0.09)
    }

    enum Typography {
        static let notchTitle = Font.subheadline.weight(.semibold)
        static let notchBody = Font.footnote
        static let notchMeta = Font.caption
        static let todoTitle = Font.footnote
        static let todoTitleDone = Font.footnote
        static let sectionLabel = Font.caption.weight(.semibold)
        static let badge = Font.caption2.weight(.bold)
        static let captionNotch = Font.caption
        static let tabLabel = Font.caption
        static let tabLabelSelected = Font.caption.weight(.semibold)
        static let actionLabel = Font.footnote
        static let section = Font.caption.weight(.semibold)
        static let cardTitle = Font.subheadline.weight(.semibold)
        static let cardCaption = Font.caption
        static let windowTitle = Font.system(size: 15, weight: .semibold)
        static let windowSubtitle = Font.caption2
    }

    enum Icon {
        static let weight: Font.Weight = .medium

        enum Size {
            static let micro: CGFloat = 10
            static let compact: CGFloat = 11
            static let standard: CGFloat = 12
            static let row: CGFloat = 13
            static let status: CGFloat = 15
            static let emphasis: CGFloat = 16
            static let hero: CGFloat = 22
        }

        enum HitTarget {
            static let toolbar: CGFloat = 28
            static let compact: CGFloat = 20
            static let formatBarHeight: CGFloat = 26
        }
    }
}

private struct NotoSymbol: View {
    let name: String
    var size: CGFloat = NotoDesign.Icon.Size.standard
    var weight: Font.Weight = NotoDesign.Icon.weight

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
    }
}

@ViewBuilder
private func notoToolbarIconButton(
    systemName: String,
    active: Bool = false,
    tint: Color? = nil,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        NotoSymbol(name: systemName)
            .foregroundStyle(tint ?? (active ? Color.primary : Color.secondary))
            .frame(width: NotoDesign.Icon.HitTarget.toolbar, height: NotoDesign.Icon.HitTarget.toolbar)
            .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
}

@ViewBuilder
private func notoFormatIconButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        NotoSymbol(name: systemName)
            .foregroundStyle(.secondary)
            .frame(width: NotoDesign.Icon.HitTarget.toolbar, height: NotoDesign.Icon.HitTarget.formatBarHeight)
            .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
}

private struct NotoProfileBadge: View {
    let name: String
    let accent: Color

    var body: some View {
        Text(name)
            .font(NotoDesign.Typography.captionNotch.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, NotoDesign.Layout.gap)
            .padding(.vertical, NotoDesign.Layout.gapTight)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.15))
            )
    }
}

// MARK: - Notch Hover Preview

/// Prevents AppKit from pushing the panel below the menu bar.
private final class NotchOverlayPanel: NSPanel {
    var keyboardInputEnabled = false {
        didSet {
            if !keyboardInputEnabled, isKeyWindow {
                resignKey()
            }
        }
    }

    override var canBecomeKey: Bool { keyboardInputEnabled }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Floating detach window — accepts keyboard for notes editing.
private final class NotchFloatingEditPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct NotchGeometry {
    let screen: NSScreen
    let notchCenterX: CGFloat
    let notchWidth: CGFloat
    let hasPhysicalNotch: Bool
    let menuBarHeight: CGFloat

    /// Menu-bar band on notched MacBooks; compact top pill on iMac / external displays.
    var bandHeight: CGFloat {
        hasPhysicalNotch ? menuBarHeight : 32
    }

    /// Idle pill matches the physical notch cutout width.
    var collapsedWidth: CGFloat {
        if hasPhysicalNotch {
            return max(notchWidth + 8, 160)
        }
        return 200
    }

    var expandedWidth: CGFloat {
        max(420, collapsedWidth + 80)
    }

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: {
            $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }) ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        let menuBarH = max(
            NSStatusBar.system.thickness,
            screen.frame.maxY - screen.visibleFrame.maxY,
            screen.safeAreaInsets.top,
            28
        )

        var notchCenterX = screen.frame.midX
        var notchWidth: CGFloat = 220
        let hasPhysicalNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchCenterX = (left.maxX + right.minX) / 2
            notchWidth = right.minX - left.maxX
        }

        return NotchGeometry(
            screen: screen,
            notchCenterX: notchCenterX,
            notchWidth: max(notchWidth, 120),
            hasPhysicalNotch: hasPhysicalNotch,
            menuBarHeight: menuBarH
        )
    }
}

// MARK: - Notch Pages (TodoStore.swift, NotesStore.swift)

private enum NotchPage: String, CaseIterable {
    case notifications
    case todo
    case notes

    var title: String {
        switch self {
        case .notifications: return "Alerts"
        case .todo: return "Todo"
        case .notes: return "Notes"
        }
    }
}

private final class NotchPanelModel: ObservableObject {
    @Published var selectedPage: NotchPage = .notifications
    @Published var events: [NotoEvent] = []
    @Published var eventIndex = 0
    @Published var isPinned = false
    @Published var isTodoDetached = false
    @Published var isNotesDetached = false
    let todoStore = NotchDailyTodoStore.shared
    let notesStore = NotchNotesStore.shared

    var isContentDetached: Bool { isTodoDetached || isNotesDetached }

    var currentEvent: NotoEvent? {
        guard !events.isEmpty else { return nil }
        return events.indices.contains(eventIndex) ? events[eventIndex] : events.first
    }
}

private struct NotchPageBar: View {
    let selected: NotchPage
    let onSelect: (NotchPage) -> Void

    var body: some View {
        Picker("Page", selection: Binding(
            get: { selected },
            set: { onSelect($0) }
        )) {
            ForEach(NotchPage.allCases, id: \.self) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: NotoDesign.NotchLayout.pageBarHeight)
    }
}

private struct NotoNotificationPager: View {
    let index: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: NotoDesign.Layout.gapTight) {
            pagerButton(systemName: "chevron.left", action: onPrevious)
            Text("\(index + 1) of \(total)")
                .font(NotoDesign.Typography.notchMeta.monospacedDigit())
                .foregroundStyle(.secondary)
            pagerButton(systemName: "chevron.right", action: onNext)
        }
    }

    private func pagerButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NotoSymbol(name: systemName, size: NotoDesign.Icon.Size.compact)
                .foregroundStyle(.secondary)
                .frame(width: NotoDesign.Icon.HitTarget.compact, height: NotoDesign.Icon.HitTarget.compact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Notch UI Helpers

private extension Color {
    static func notchWhite(_ opacity: Double) -> Color {
        Color.white.opacity(opacity)
    }
}

private extension View {
    @ViewBuilder
    func notchFloatingShell(cornerRadius: CGFloat = NotoDesign.Radius.notch) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(NotoDesign.NotchColor.stroke, lineWidth: 0.5)
                    }
            }
        }
    }
}

private struct NotchGroupedSurface: ViewModifier {
    var cornerRadius: CGFloat = NotoDesign.Radius.card

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(NotoDesign.NotchColor.stroke, lineWidth: 0.5)
                }
        }
    }
}

private extension View {
    func notchGroupedSurface(cornerRadius: CGFloat = NotoDesign.Radius.card) -> some View {
        modifier(NotchGroupedSurface(cornerRadius: cornerRadius))
    }

    /// Equal margin on all four sides of a notch page shell.
    func notchShellPadding() -> some View {
        padding(NotoDesign.Layout.margin)
    }

    /// Symmetric horizontal inset with optional vertical inset for grouped surfaces.
    func notchSurfacePadding(vertical: CGFloat = NotoDesign.Layout.insetTight) -> some View {
        padding(.horizontal, NotoDesign.Layout.inset)
            .padding(.vertical, vertical)
    }

    func notchPanelDivider(leadingInset: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, leadingInset)
        }
    }

    func notchFormRowDivider(leadingInset: CGFloat = 0) -> some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

/// Two-column toolbar with equal-width leading and trailing groups for visual balance.
private struct NotchBalancedToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: NotoDesign.Layout.gapTight) {
                leading()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: NotoDesign.Layout.gapTight) {
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .notchSurfacePadding(vertical: NotoDesign.Layout.gapTight)
        .frame(height: NotoDesign.Layout.toolbarHeight)
    }
}

private struct NotchTodoMetaHeader<Trailing: View>: View {
    let dateLabel: String
    let doneCount: Int
    let totalCount: Int
    var badge: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        LabeledContent {
            HStack(spacing: NotoDesign.Layout.gapTight) {
                trailing()
                if let badge {
                    NotchMetaBadge(text: badge)
                }
                if totalCount > 0 {
                    Text("\(doneCount)/\(totalCount)")
                        .font(NotoDesign.Typography.notchMeta.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(dateLabel)
                .font(NotoDesign.Typography.notchBody)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(height: NotoDesign.NotchLayout.todoMetaHeight, alignment: .center)
    }
}

@ViewBuilder
private func notchGhostButton(title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.borderless)
        .font(NotoDesign.Typography.captionNotch)
        .foregroundStyle(.secondary)
        .controlSize(.small)
}

private struct NotchInlineBanner: View {
    let icon: String
    let tint: Color
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: NotoDesign.Layout.gap) {
            NotoSymbol(name: icon, size: NotoDesign.Icon.Size.compact)
                .foregroundStyle(tint)
            Text(message)
                .font(NotoDesign.Typography.captionNotch)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                notchGhostButton(title: actionTitle, action: action)
            }
        }
        .padding(.horizontal, NotoDesign.Layout.inset)
        .frame(height: NotoDesign.NotchLayout.todoBannerHeight)
        .background(
            RoundedRectangle(cornerRadius: NotoDesign.Radius.control, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotoDesign.Radius.control, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct NotchMetaBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(NotoDesign.Typography.sectionLabel)
            .foregroundStyle(.secondary)
            .padding(.horizontal, NotoDesign.Layout.gap)
            .padding(.vertical, NotoDesign.Layout.gapTight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

private struct NotchTodoSectionHeader: View {
    let title: String
    var count: Int? = nil
    var collapsible: Bool = false
    var expanded: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if collapsible, let action {
                Button(action: action) {
                    headerContent
                }
                .buttonStyle(.plain)
            } else {
                headerContent
            }
        }
        .frame(height: NotoDesign.NotchLayout.todoSectionHeaderHeight, alignment: .leading)
    }

    @ViewBuilder
    private var headerContent: some View {
        HStack(spacing: NotoDesign.Layout.gapTight) {
            Text(title)
                .font(NotoDesign.Typography.section)
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(NotoDesign.Typography.section)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, NotoDesign.Layout.gapTight)
                    .padding(.vertical, NotoDesign.Layout.gapTight / 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            if collapsible {
                NotoSymbol(
                    name: expanded ? "chevron.down" : "chevron.right",
                    size: NotoDesign.Icon.Size.micro
                )
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct NotchAlertsPageView: View {
    let display: NotoNotificationDisplay
    let relativeTime: String?
    let index: Int
    let total: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var accent: Color { display.profile.accentColor }

    private var metaLine: String {
        if !display.subtitle.isEmpty { return display.notchMeta }
        if let relativeTime, !relativeTime.isEmpty {
            return ProfileSettings.notchMetaText(relativeTime)
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.Layout.gap) {
            LabeledContent {
                if total > 1 {
                    NotoNotificationPager(
                        index: index,
                        total: total,
                        onPrevious: onPrevious,
                        onNext: onNext
                    )
                }
            } label: {
                HStack(spacing: NotoDesign.Layout.gap) {
                    NotoProfileBadge(name: display.profile.label, accent: accent)
                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(NotoDesign.Typography.notchMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(height: NotoDesign.NotchLayout.headerHeight, alignment: .center)

            VStack(alignment: .leading, spacing: NotoDesign.Layout.gapTight) {
                Text(display.notchTitle)
                    .font(NotoDesign.Typography.notchTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(display.notchBody)
                    .font(NotoDesign.Typography.notchBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NotoDesign.NotchLayout.alertsCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notchGroupedSurface()
            .frame(height: NotoDesign.NotchLayout.alertsContentHeight, alignment: .topLeading)
        }
        .frame(height: NotoDesign.NotchLayout.alertsBodyHeight, alignment: .topLeading)
    }
}

private final class NotchFirstClickTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct NotchTodoTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onBeginEditing: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NotchFirstClickTextField(string: "")
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.textColor = NSColor.labelColor
        field.font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .footnote).pointSize)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onBeginEditing = onBeginEditing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onBeginEditing: onBeginEditing)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onBeginEditing: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onBeginEditing: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onBeginEditing = onBeginEditing
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            onBeginEditing()
        }

        @objc func submit(_ sender: NSTextField) {
            text = sender.stringValue
            onSubmit()
        }
    }
}

private struct NotchTodoRowChrome: View {
    @ObservedObject var store: NotchDailyTodoStore
    let item: NotchTodoItem
    let editable: Bool
    let onActivity: () -> Void

    var body: some View {
        HStack(spacing: NotoDesign.NotchLayout.todoRowInnerSpacing) {
            Button {
                store.toggle(item.id)
                onActivity()
            } label: {
                NotoSymbol(
                    name: item.isDone ? "checkmark.circle.fill" : "circle",
                    size: NotoDesign.Icon.Size.status
                )
                .foregroundStyle(item.isDone ? NotoDesign.NotchAccent.done : Color.notchWhite(NotoDesign.NotchOpacity.tertiary))
                .frame(width: NotoDesign.Icon.HitTarget.compact, height: NotoDesign.Icon.HitTarget.compact)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(item.isDone ? NotoDesign.Typography.todoTitleDone : NotoDesign.Typography.todoTitle)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .strikethrough(item.isDone, color: Color.secondary.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.origin == .teevoHub {
                Text("Hub")
                    .font(NotoDesign.Typography.badge)
                    .foregroundStyle(NotoDesign.NotchAccent.hub)
                    .padding(.horizontal, NotoDesign.Layout.gapTight)
                    .padding(.vertical, NotoDesign.Layout.gapTight / 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(NotoDesign.NotchAccent.hub.opacity(0.12))
                    )
            } else if item.origin == .rolled {
                NotoSymbol(name: "arrow.uturn.backward", size: NotoDesign.Icon.Size.micro)
                    .foregroundStyle(NotoDesign.NotchAccent.roll.opacity(0.85))
            }

            if editable, !item.isDone {
                Menu {
                    if item.section == .today {
                        Button("Move to Now") {
                            store.moveSection(item.id, to: .now)
                            onActivity()
                        }
                    } else {
                        Button("Move to Today") {
                            store.moveSection(item.id, to: .today)
                            onActivity()
                        }
                    }
                    if item.origin != .teevoHub {
                        Button("Repeat: \(item.repeatRule.label)") {
                            store.cycleRepeat(item.id)
                            onActivity()
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.remove(item.id)
                        onActivity()
                    }
                } label: {
                    NotoSymbol(name: "ellipsis.circle", size: NotoDesign.Icon.Size.row)
                        .foregroundStyle(.secondary)
                        .frame(width: NotoDesign.Icon.HitTarget.compact, height: NotoDesign.Icon.HitTarget.compact)
                }
                .menuStyle(.borderlessButton)
            }

            if editable, item.isDone {
                Button {
                    store.remove(item.id)
                    onActivity()
                } label: {
                    NotoSymbol(name: "xmark.circle.fill", size: NotoDesign.Icon.Size.row)
                        .foregroundStyle(.secondary)
                        .frame(width: NotoDesign.Icon.HitTarget.compact, height: NotoDesign.Icon.HitTarget.compact)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: NotoDesign.NotchLayout.todoRowHeight, alignment: .center)
    }
}

private struct NotchTodoSectionsList: View {
    @ObservedObject var store: NotchDailyTodoStore
    var editable: Bool = false
    var onActivity: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.rowGap) {
            if store.rolledBannerCount > 0 {
                NotchInlineBanner(
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: NotoDesign.NotchAccent.roll,
                    message: "\(store.rolledBannerCount) rolled from yesterday",
                    actionTitle: "Dismiss",
                    action: { store.dismissRolledBanner() }
                )
            }

            if store.hiddenHubOpenCount > 0 {
                NotchInlineBanner(
                    icon: "eye.slash.fill",
                    tint: NotoDesign.NotchAccent.hub,
                    message: "\(store.hiddenHubOpenCount) Hub todo\(store.hiddenHubOpenCount == 1 ? "" : "s") hidden",
                    actionTitle: editable ? "Show" : nil,
                    action: editable ? {
                        store.setHubTodosVisible(true)
                        onActivity()
                    } : nil
                )
            }

            if store.visibleItems.isEmpty {
                Label {
                    Text(editable ? "No tasks yet — add one below." : "No tasks for today.")
                        .font(NotoDesign.Typography.notchBody)
                        .foregroundStyle(.secondary)
                } icon: {
                    NotoSymbol(name: "checklist")
                        .foregroundStyle(.tertiary)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, NotoDesign.Layout.inset)
                .frame(maxWidth: .infinity, minHeight: NotoDesign.NotchLayout.todoEmptyListHeight, alignment: .leading)
                .notchGroupedSurface()
            } else {
                todoGroupedList
            }
        }
    }

    @ViewBuilder
    private var todoGroupedList: some View {
        VStack(spacing: 0) {
            if !store.nowItems.isEmpty {
                sectionBlock(title: "Now", items: store.nowItems, showHeader: true, topPadding: false)
            }

            if !store.todayItems.isEmpty || store.nowItems.isEmpty {
                sectionBlock(
                    title: "Today",
                    items: store.todayItems,
                    showHeader: !store.nowItems.isEmpty,
                    topPadding: !store.nowItems.isEmpty
                )
            }

            if !store.doneItems.isEmpty {
                doneSectionBlock
            }
        }
        .notchGroupedSurface()
    }

    @ViewBuilder
    private func sectionBlock(
        title: String,
        items: [NotchTodoItem],
        showHeader: Bool,
        topPadding: Bool
    ) -> some View {
        if showHeader {
            if topPadding {
                notchFormRowDivider()
            }
            NotchTodoSectionHeader(title: title)
                .padding(.horizontal, NotoDesign.Layout.inset)
                .padding(.top, topPadding ? NotoDesign.Layout.gapTight : NotoDesign.Layout.gap)
                .padding(.bottom, NotoDesign.Layout.gapTight)
        }
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 || showHeader {
                notchFormRowDivider()
            }
            NotchTodoRowChrome(store: store, item: item, editable: editable, onActivity: onActivity)
                .padding(.horizontal, NotoDesign.Layout.inset)
        }
    }

    @ViewBuilder
    private var doneSectionBlock: some View {
        notchFormRowDivider()
        NotchTodoSectionHeader(
            title: "Done",
            count: store.doneItems.count,
            collapsible: true,
            expanded: store.doneSectionExpanded,
            action: {
                store.doneSectionExpanded.toggle()
                onActivity()
            }
        )
        .padding(.horizontal, NotoDesign.Layout.inset)
        .padding(.vertical, NotoDesign.Layout.gapTight)

        let visibleDone = store.doneSectionExpanded ? store.doneItems : Array(store.doneItems.prefix(2))
        ForEach(Array(visibleDone.enumerated()), id: \.element.id) { index, item in
            notchFormRowDivider()
            NotchTodoRowChrome(store: store, item: item, editable: editable, onActivity: onActivity)
                .padding(.horizontal, NotoDesign.Layout.inset)
        }
        if !store.doneSectionExpanded, store.doneItems.count > 2 {
            notchFormRowDivider()
            Text("\(store.doneItems.count - 2) more completed")
                .font(NotoDesign.Typography.captionNotch)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, NotoDesign.Layout.inset)
                .frame(height: NotoDesign.NotchLayout.doneOverflowHeight, alignment: .leading)
        }
    }
}

private struct NotchTodoPreviewView: View {
    @ObservedObject var store: NotchDailyTodoStore
    var onActivity: () -> Void = {}

    private var doneCount: Int { store.doneItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.sectionGap) {
            NotchTodoMetaHeader(
                dateLabel: "Today · \(NotchDailyTodoStore.todayLabel())",
                doneCount: doneCount,
                totalCount: store.visibleItems.count,
                badge: "Preview"
            ) {
                EmptyView()
            }

            NotchTodoSectionsList(store: store, editable: false, onActivity: onActivity)
        }
        .frame(
            height: NotoDesign.NotchLayout.todoPreviewBodyHeight(
                metrics: store.layoutMetrics,
                doneExpanded: store.doneSectionExpanded
            ),
            alignment: .topLeading
        )
        .onAppear { store.refreshDayIfNeeded() }
    }
}

private struct NotchTodoFloatingContent: View {
    @ObservedObject var store: NotchDailyTodoStore
    let onAttach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.sectionGap) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onAttach) {
                    Label("Attach", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(NotoDesign.Typography.captionNotch.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, NotoDesign.Layout.gap)
                        .padding(.vertical, NotoDesign.Layout.gapTight)
                        .notchGroupedSurface()
                        .contentShape(RoundedRectangle(cornerRadius: NotoDesign.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Return todo to notch")
            }

            NotchTodoPreviewView(store: store)
        }
        .notchShellPadding()
        .frame(width: 300)
        .notchFloatingShell()
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .preferredColorScheme(.dark)
    }
}

private final class NotchFloatingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private struct NotchTodoPageView: View {
    @ObservedObject var store: NotchDailyTodoStore
    let onActivity: () -> Void

    @State private var draft = ""
    let onBeginEditing: () -> Void

    private var doneCount: Int { store.doneItems.count }
    private var draftTrimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !draftTrimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.sectionGap) {
            NotchTodoMetaHeader(
                dateLabel: "Today · \(NotchDailyTodoStore.todayLabel())",
                doneCount: doneCount,
                totalCount: store.visibleItems.count
            ) {
                if store.hub.enabled {
                    HStack(spacing: NotoDesign.Layout.gapTight) {
                        notoToolbarIconButton(
                            systemName: store.hub.showInList ? "eye" : "eye.slash",
                            active: store.hub.showInList,
                            action: {
                                store.setHubTodosVisible(!store.hub.showInList)
                                onActivity()
                            }
                        )
                        .help(store.hub.showInList ? "Hide Teevo Hub todos" : "Show Teevo Hub todos")
                        notoToolbarIconButton(
                            systemName: store.isSyncingHub ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                            active: store.isSyncingHub,
                            action: { store.syncHubNow(); onActivity() }
                        )
                        .help("Sync Teevo Hub todos")
                    }
                }
            }

            NotchTodoSectionsList(store: store, editable: true, onActivity: onActivity)

            HStack(spacing: NotoDesign.Layout.gap) {
                NotchTodoTextField(
                    text: $draft,
                    placeholder: "Add a task…",
                    onSubmit: submitDraft,
                    onBeginEditing: onBeginEditing
                )
                .frame(maxWidth: .infinity)

                Menu {
                    ForEach(store.templates) { template in
                        Button(template.name) {
                            store.applyTemplate(template.id)
                            onActivity()
                        }
                    }
                } label: {
                    NotoSymbol(name: "doc.on.doc")
                        .foregroundStyle(store.templates.isEmpty ? .tertiary : .secondary)
                        .frame(width: NotoDesign.Icon.HitTarget.toolbar, height: NotoDesign.Icon.HitTarget.toolbar)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .disabled(store.templates.isEmpty)
                .help("Insert template")

                Button(action: submitDraft) {
                    NotoSymbol(name: "plus.circle.fill", size: NotoDesign.Icon.Size.emphasis)
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: NotoDesign.Icon.HitTarget.toolbar, height: NotoDesign.Icon.HitTarget.toolbar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, NotoDesign.Layout.inset)
            .padding(.vertical, NotoDesign.Layout.gapTight)
            .frame(height: NotoDesign.NotchLayout.todoAddHeight)
            .notchGroupedSurface()
        }
        .frame(
            height: NotoDesign.NotchLayout.todoBodyHeight(
                metrics: store.layoutMetrics,
                doneExpanded: store.doneSectionExpanded
            ),
            alignment: .topLeading
        )
        .onAppear { store.refreshDayIfNeeded() }
    }

    private func submitDraft() {
        guard canSubmit else { return }
        store.add(draftTrimmed)
        draft = ""
        onActivity()
    }
}

private final class NotchFirstClickScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct NotchNotesTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let bridge: NotchNotesTextBridge
    let fontSize: CGFloat
    let onBeginEditing: () -> Void
    let onEdit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NotchFirstClickScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.clipsToBounds = true

        let view = NSTextView()
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.textColor = NSColor.labelColor
        view.insertionPointColor = NSColor(red: 0.95, green: 0.35, blue: 0.32, alpha: 1)
        view.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.textContainer?.lineFragmentPadding = 0
        view.delegate = context.coordinator
        scroll.documentView = view
        context.coordinator.textView = view
        bridge.coordinator = context.coordinator
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let view = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onEdit = onEdit
        context.coordinator.onBeginEditing = onBeginEditing
        bridge.coordinator = context.coordinator

        if view.string != text {
            view.string = text
        }

        let maxLoc = (view.string as NSString).length
        let loc = min(max(0, selectedRange.location), maxLoc)
        let len = min(max(0, selectedRange.length), maxLoc - loc)
        let desired = NSRange(location: loc, length: len)
        if view.selectedRange() != desired {
            view.setSelectedRange(desired)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, onBeginEditing: onBeginEditing, onEdit: onEdit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NotchNotesFormatTarget {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        var onBeginEditing: () -> Void
        var onEdit: () -> Void
        weak var textView: NSTextView?

        init(
            text: Binding<String>,
            selectedRange: Binding<NSRange>,
            onBeginEditing: @escaping () -> Void,
            onEdit: @escaping () -> Void
        ) {
            _text = text
            _selectedRange = selectedRange
            self.onBeginEditing = onBeginEditing
            self.onEdit = onEdit
        }

        func applyFormat(_ action: NotchNotesFormatAction) {
            guard let view = textView else { return }
            let range = view.selectedRange()
            let result = NotchNotesMarkdown.apply(action, to: text, selectedRange: range)
            text = result.0
            selectedRange = result.1
            view.string = result.0
            view.setSelectedRange(result.1)
            onEdit()
        }

        func focusEditor() {
            guard let view = textView else { return }
            view.window?.makeFirstResponder(view)
        }

        func textDidBeginEditing(_ notification: Notification) {
            onBeginEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text = view.string
            selectedRange = view.selectedRange()
            onEdit()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            selectedRange = view.selectedRange()
        }
    }
}

private struct NotchNotesFormatBar: View {
    let bridge: NotchNotesTextBridge
    let compact: Bool

    var body: some View {
        HStack(spacing: NotoDesign.Layout.gap) {
            if compact {
                notoFormatIconButton(systemName: "textformat.size") { bridge.apply(.heading(2)) }
                notoFormatIconButton(systemName: "bold") { bridge.apply(.bold) }
                notoFormatIconButton(systemName: "list.bullet") { bridge.apply(.bulletList) }
            } else {
                notoFormatIconButton(systemName: "textformat.size.larger") { bridge.apply(.heading(1)) }
                notoFormatIconButton(systemName: "textformat.size") { bridge.apply(.heading(2)) }
                notoFormatIconButton(systemName: "bold") { bridge.apply(.bold) }
                notoFormatIconButton(systemName: "italic") { bridge.apply(.italic) }
                notesFormatDivider
                notoFormatIconButton(systemName: "link") { bridge.apply(.link) }
                notoFormatIconButton(systemName: "chevron.left.forwardslash.chevron.right") { bridge.apply(.inlineCode) }
                notesFormatDivider
                notoFormatIconButton(systemName: "list.bullet") { bridge.apply(.bulletList) }
                notoFormatIconButton(systemName: "checklist") { bridge.apply(.taskList) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .notchSurfacePadding(vertical: NotoDesign.Layout.gapTight)
        .frame(height: NotoDesign.NotchLayout.notesFormatBarHeight)
    }

    private var notesFormatDivider: some View {
        Divider()
            .frame(height: NotoDesign.Layout.dividerHeight)
    }
}

private struct NotchNotesBrowsePanel: View {
    @ObservedObject var store: NotchNotesStore
    let onSelectPage: (UUID) -> Void
    let onActivity: () -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NotoDesign.Layout.gap) {
                NotoSymbol(name: "magnifyingglass")
                    .foregroundStyle(.secondary)
                NotchTodoTextField(
                    text: $store.browseQuery,
                    placeholder: "Search notes…",
                    onSubmit: {},
                    onBeginEditing: onBeginEditing
                )
            }
            .notchSurfacePadding(vertical: NotoDesign.Layout.gapTight)
            .frame(height: NotoDesign.NotchLayout.notesBrowseSearchHeight)
            .notchPanelDivider()

            if store.browsablePages.isEmpty {
                Text("No matching notes")
                    .font(NotoDesign.Typography.notchMeta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .notchSurfacePadding(vertical: NotoDesign.Layout.gap)
                    .frame(height: NotoDesign.NotchLayout.notesBrowseRowHeight)
            } else {
                ForEach(Array(store.browsablePages.prefix(8).enumerated()), id: \.element.id) { index, page in
                    if index > 0 {
                        notchFormRowDivider()
                    }
                    NotchNotesBrowseRow(
                        store: store,
                        page: page,
                        onSelect: { onSelectPage(page.id) },
                        onActivity: onActivity
                    )
                }
            }
        }
    }
}

private struct NotchNotesBrowseRow: View {
    @ObservedObject var store: NotchNotesStore
    let page: NotchNotePage
    let onSelect: () -> Void
    let onActivity: () -> Void

    private var isSelected: Bool { store.activePage?.id == page.id }

    private var previewText: String {
        let raw = page.body.replacingOccurrences(of: "\n", with: " ")
        let plain = ProfileSettings.plainTextForNotch(raw)
        return plain.isEmpty ? "No content" : plain
    }

    var body: some View {
        HStack(alignment: .center, spacing: NotoDesign.Layout.gap) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.notesRowTitleGap) {
                    Text(NotchNotesMarkdown.displayTitle(for: page.body, fallback: page.title))
                        .font(NotoDesign.Typography.notchBody)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(previewText)
                        .font(NotoDesign.Typography.notchMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(NotchNotesStore.relativeDate(page.updatedAt))
                .font(NotoDesign.Typography.notchMeta.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)

            HStack(spacing: NotoDesign.Layout.gapTight) {
                notoToolbarIconButton(
                    systemName: page.isPinned ? "pin.fill" : "pin",
                    active: page.isPinned,
                    action: {
                        store.togglePagePin(page.id)
                        onActivity()
                    }
                )
                .help(page.isPinned ? "Unpin note" : "Pin note")

                notoToolbarIconButton(systemName: "trash") {
                    store.deletePage(page.id)
                    onActivity()
                }
                .help("Delete note")
            }
        }
        .notchSurfacePadding(vertical: NotoDesign.Layout.gap)
        .frame(height: NotoDesign.NotchLayout.notesBrowseRowHeight)
        .background(
            isSelected ? Color.primary.opacity(0.08) : Color.clear
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open") { onSelect() }
            Button(page.isPinned ? "Unpin" : "Pin") {
                store.togglePagePin(page.id)
                onActivity()
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.deletePage(page.id)
                onActivity()
            }
        }
    }
}

private struct NotchNotesEditorChrome: View {
    @ObservedObject var store: NotchNotesStore
    let floating: Bool
    var onAttach: (() -> Void)? = nil
    var onDetach: (() -> Void)? = nil
    let onActivity: () -> Void
    let onBeginEditing: () -> Void

    @State private var bodyDraft = ""
    @State private var loadedPageId: UUID?
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var textBridge = NotchNotesTextBridge()

    private var editorHeight: CGFloat {
        floating
            ? NotoDesign.NotchLayout.notesFloatingEditorHeight
            : NotoDesign.NotchLayout.notesEditorHeight
    }

    private var isEmpty: Bool {
        bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NotchBalancedToolbar {
                Group {
                    if let onAttach {
                        notchGhostButton(title: "Attach", action: onAttach)
                    } else if let onDetach {
                        notoToolbarIconButton(systemName: "rectangle.portrait.and.arrow.right", action: onDetach)
                            .help("Pop out notes")
                    }
                }
            } trailing: {
                Group {
                    if !store.browseExpanded, store.canDeleteActivePage {
                        notoToolbarIconButton(systemName: "trash") {
                            store.deleteActivePage()
                            reloadDraftFromStore()
                            onActivity()
                        }
                        .help("Delete note")
                    }
                    notoToolbarIconButton(systemName: "plus") {
                        _ = store.createPage()
                        reloadDraftFromStore()
                        focusEditor()
                        onActivity()
                    }
                    .help("New note (⌘N)")
                    notoToolbarIconButton(
                        systemName: store.browseExpanded ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                        active: store.browseExpanded
                    ) {
                        store.toggleBrowse()
                        onActivity()
                    }
                    .help("Browse notes")
                }
            }
            .notchPanelDivider()

            if store.browseExpanded {
                NotchNotesBrowsePanel(
                    store: store,
                    onSelectPage: openPageFromBrowse,
                    onActivity: onActivity,
                    onBeginEditing: onBeginEditing
                )
                .notchPanelDivider()
            } else {
                ZStack(alignment: .topLeading) {
                    if isEmpty {
                        Text("Start writing…")
                            .font(NotoDesign.Typography.notchBody)
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                    NotchNotesTextView(
                        text: $bodyDraft,
                        selectedRange: $selectedRange,
                        bridge: textBridge,
                        fontSize: floating ? 13 : NSFont.preferredFont(forTextStyle: .footnote).pointSize,
                        onBeginEditing: onBeginEditing,
                        onEdit: {
                            store.updateActiveBody(bodyDraft)
                        }
                    )
                }
                .notchSurfacePadding()
                .frame(height: editorHeight, alignment: .topLeading)
                .clipped()
                .notchPanelDivider()
            }

            NotchNotesFormatBar(bridge: textBridge, compact: !floating)
        }
        .notchGroupedSurface()
        .frame(
            height: NotoDesign.NotchLayout.notesBodyHeight(metrics: store.layoutMetrics, floating: floating),
            alignment: .topLeading
        )
        .onAppear { reloadDraftFromStore() }
        .onChange(of: store.activePageId) { _, newId in
            guard newId != loadedPageId else { return }
            reloadDraftFromStore()
        }
        .onChange(of: store.browseExpanded) { _, expanded in
            if !expanded {
                reloadDraftFromStore()
                DispatchQueue.main.async {
                    focusEditor()
                }
            }
        }
    }

    private func openPageFromBrowse(_ id: UUID) {
        store.selectPage(id)
        store.closeBrowse()
        reloadDraftFromStore()
        onBeginEditing()
        onActivity()
        DispatchQueue.main.async {
            focusEditor()
        }
    }

    private func focusEditor() {
        onBeginEditing()
        textBridge.focusEditor()
    }

    private func reloadDraftFromStore() {
        guard let page = store.activePage else { return }
        loadedPageId = page.id
        bodyDraft = NotchNotesStore.sanitizeBody(page.body)
        selectedRange = NSRange(location: (bodyDraft as NSString).length, length: 0)
    }
}

private struct NotchNotesPageView: View {
    @ObservedObject var store: NotchNotesStore
    let onDetach: () -> Void
    let onActivity: () -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        NotchNotesEditorChrome(
            store: store,
            floating: false,
            onDetach: onDetach,
            onActivity: onActivity,
            onBeginEditing: onBeginEditing
        )
    }
}

private struct NotchNotesDetachedHint: View {
    let onAttach: () -> Void

    var body: some View {
        VStack(spacing: NotoDesign.Space.md) {
            NotoSymbol(name: "note.text", size: NotoDesign.Icon.Size.hero)
                .foregroundStyle(.tertiary)
            Text("Notes are in the floating window")
                .font(NotoDesign.Typography.captionNotch)
                .foregroundStyle(.secondary)
            notchGhostButton(title: "Attach to notch", action: onAttach)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NotoDesign.NotchLayout.alertsBodyHeight, alignment: .center)
    }
}

private struct NotchNotesFloatingContent: View {
    @ObservedObject var store: NotchNotesStore
    let onAttach: () -> Void
    let onActivity: () -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        NotchNotesEditorChrome(
            store: store,
            floating: true,
            onAttach: onAttach,
            onActivity: onActivity,
            onBeginEditing: onBeginEditing
        )
        .notchShellPadding()
        .frame(width: NotoDesign.NotchLayout.notesFloatingWidth, alignment: .topLeading)
        .notchFloatingShell()
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .preferredColorScheme(.dark)
    }
}

private struct NotchPanelContent: View {
    @ObservedObject var model: NotchPanelModel
    var showsOpenButton: Bool = true
    let onSelectPage: (NotchPage) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOpenSettings: () -> Void
    let onOpen: () -> Void
    let onActivity: () -> Void
    let onBeginEditing: () -> Void
    let onPinToggle: (Bool) -> Void
    let onDetachTodo: () -> Void
    let onDetachNotes: () -> Void
    let onAttachNotes: () -> Void

    private var idleEvent: NotoEvent {
        NotoEvent(
            id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            profile: "Noto",
            kind: "idle",
            title: "No notifications yet",
            subtitle: "",
            body: "Finish an agent task to see recent activity here.",
            sound: "",
            delivered: true,
            suppressReason: nil,
            openApp: nil
        )
    }

    private var pageBarTrailingWidth: CGFloat {
        let count = (model.selectedPage == .todo && !model.isTodoDetached) ? 2 : 1
        return CGFloat(count) * NotoDesign.Icon.HitTarget.toolbar
            + CGFloat(max(0, count - 1)) * NotoDesign.Layout.gapTight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotoDesign.NotchLayout.sectionGap) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: pageBarTrailingWidth)
                    .accessibilityHidden(true)
                NotchPageBar(selected: model.selectedPage, onSelect: onSelectPage)
                    .frame(maxWidth: .infinity)
                HStack(spacing: NotoDesign.Layout.gapTight) {
                    if model.selectedPage == .todo, !model.isTodoDetached {
                        notoToolbarIconButton(systemName: "rectangle.portrait.and.arrow.right", action: onDetachTodo)
                            .help("Detach todo to floating window")
                    }
                    notoToolbarIconButton(
                        systemName: model.isPinned ? "pin.fill" : "pin",
                        active: model.isPinned,
                        action: {
                            let pinned = !model.isPinned
                            model.isPinned = pinned
                            onPinToggle(pinned)
                        }
                    )
                    .help(model.isPinned ? "Unpin notch" : "Keep notch open")
                }
                .frame(width: pageBarTrailingWidth, alignment: .trailing)
            }
            .frame(height: NotoDesign.NotchLayout.pageBarHeight)
            .frame(maxWidth: .infinity)

            Group {
                switch model.selectedPage {
                case .notifications:
                    let event = model.currentEvent ?? idleEvent
                    NotchAlertsPageView(
                        display: event.display(),
                        relativeTime: model.currentEvent.map { NotoEventLog.relativeTime(since: $0.date) },
                        index: model.eventIndex,
                        total: max(model.events.count, 1),
                        onPrevious: onPrevious,
                        onNext: onNext
                    )
                case .todo:
                    if model.isTodoDetached {
                        NotchTodoPreviewView(store: model.todoStore)
                    } else {
                        NotchTodoPageView(
                            store: model.todoStore,
                            onActivity: onActivity,
                            onBeginEditing: onBeginEditing
                        )
                    }
                case .notes:
                    if model.isNotesDetached {
                        NotchNotesDetachedHint(onAttach: onAttachNotes)
                    } else {
                        NotchNotesPageView(
                            store: model.notesStore,
                            onDetach: onDetachNotes,
                            onActivity: onActivity,
                            onBeginEditing: onBeginEditing
                        )
                    }
                }
            }

            if showsOpenButton, model.selectedPage == .notifications {
                let accent = (model.currentEvent ?? idleEvent).display().profile.accentColor
                HStack(spacing: NotoDesign.Layout.gap) {
                    notchSecondaryActionButton(title: "Open Settings", action: onOpenSettings)
                    if let event = model.currentEvent {
                        notchPrimaryActionButton(
                            title: "Open \(event.display().profile.label)",
                            accent: accent,
                            action: onOpen
                        )
                    } else {
                        notchPrimaryActionButton(title: "Open Cursor", accent: accent, action: onOpen)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: NotoDesign.NotchLayout.buttonHeight)
            }
        }
        .notchShellPadding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .preferredColorScheme(.dark)
    }

    private func notchSecondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notchPrimaryActionButton(title: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// AppKit shell: flat top flush with screen, rounded bottom, grabber in menu-bar band.
private final class NotchIslandRootView: NSView {
    var bandHeight: CGFloat = 30
    var contentHeight: CGFloat = 86
    var bottomRadius: CGFloat = NotoDesign.Radius.notch
    var showsExpandedBody = false
    var hasPhysicalNotch = false
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}

    private var hostingView: NSHostingView<NotchPanelContent>?
    private var effectView: NSVisualEffectView?
    private var redrawTimer: Timer?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .underWindowBackground
        effect.autoresizingMask = [.width, .height]
        effect.isHidden = true
        addSubview(effect)
        effectView = effect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    func mount(_ content: NotchPanelContent) {
        hostingView?.removeFromSuperview()
        let host = NSHostingView(rootView: content)
        host.alphaValue = showsExpandedBody ? contentAlpha : 0
        hostingView = host
        addSubview(host)
        needsLayout = true
        syncHostingVisibility()
    }

    var contentAlpha: CGFloat = 1 {
        didSet { syncHostingVisibility() }
    }

    private var shouldShowContent: Bool {
        showsExpandedBody && bounds.height > bandHeight + 4
    }

    private func syncHostingVisibility() {
        guard let hostingView else { return }
        if shouldShowContent {
            hostingView.isHidden = false
            hostingView.alphaValue = contentAlpha
        } else {
            hostingView.isHidden = true
            hostingView.alphaValue = 0
        }
    }

    func setContentAlpha(_ alpha: CGFloat, animated: Bool, duration: TimeInterval = 0.18) {
        contentAlpha = alpha
        guard animated, let hostingView, shouldShowContent else {
            syncHostingVisibility()
            return
        }
        hostingView.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            hostingView.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            self?.syncHostingVisibility()
        }
    }

    func prepareContentHidden() {
        contentAlpha = 0
        syncHostingVisibility()
    }

    override func layout() {
        super.layout()
        effectView?.frame = bounds
        effectView?.isHidden = !usesExpandedShape
        if shouldShowContent {
            hostingView?.frame = NSRect(
                x: 0,
                y: bandHeight,
                width: bounds.width,
                height: contentHeight
            )
        } else {
            hostingView?.frame = .zero
        }
        syncHostingVisibility()
        updateExpandedClip()
        updateTrackingAreas()
    }

    private func updateExpandedClip() {
        guard let layer else { return }
        guard showsExpandedBody, bounds.height > bandHeight + 2 else {
            layer.mask = nil
            return
        }
        let radius = min(bottomRadius, bounds.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: bounds.width, y: 0))
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height - radius))
        path.addArc(
            tangent1End: CGPoint(x: bounds.width, y: bounds.height),
            tangent2End: CGPoint(x: bounds.width - radius, y: bounds.height),
            radius: radius
        )
        path.addLine(to: CGPoint(x: radius, y: bounds.height))
        path.addArc(
            tangent1End: CGPoint(x: 0, y: bounds.height),
            tangent2End: CGPoint(x: 0, y: bounds.height - radius),
            radius: radius
        )
        path.closeSubpath()
        let mask = CAShapeLayer()
        mask.path = path
        layer.mask = mask
    }

    /// Grabber rides the morphing shell — position follows live panel height (no separate animation).
    private func grabberOriginY(for viewHeight: CGFloat) -> CGFloat {
        if hasPhysicalNotch {
            return (min(bandHeight, viewHeight) - 4) / 2
        }
        let collapsedH = bandHeight
        let expandedH = bandHeight + contentHeight
        let collapsedY = collapsedH - 10
        let expandedY: CGFloat = 8
        if viewHeight <= collapsedH + 0.5 { return collapsedY }
        if viewHeight >= expandedH - 0.5 { return expandedY }
        let t = (viewHeight - collapsedH) / max(expandedH - collapsedH, 1)
        return collapsedY + (expandedY - collapsedY) * t
    }

    private func drawGrabber(in bounds: NSRect) {
        let y = grabberOriginY(for: bounds.height)
        let grabberWidth: CGFloat = 32
        let grabberHeight: CGFloat = 3
        let path = NSBezierPath(
            roundedRect: NSRect(
                x: bounds.midX - grabberWidth / 2,
                y: y,
                width: grabberWidth,
                height: grabberHeight
            ),
            xRadius: grabberHeight / 2,
            yRadius: grabberHeight / 2
        )
        NotoDesign.NotchPalette.grabber.setFill()
        path.fill()
    }

    func beginContinuousRedraw() {
        endContinuousRedraw()
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.layoutSubtreeIfNeeded()
            self?.needsDisplay = true
        }
    }

    func endContinuousRedraw() {
        redrawTimer?.invalidate()
        redrawTimer = nil
        needsDisplay = true
    }

    private var usesExpandedShape: Bool {
        showsExpandedBody || bounds.height > bandHeight + 2
    }

    private func drawCollapsedPill(in bounds: NSRect) {
        let h = min(bandHeight, bounds.height)
        let radius = min(NotoDesign.Radius.pill, h / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: bounds.width, y: 0))
        path.line(to: NSPoint(x: bounds.width, y: h - radius))
        path.appendArc(
            withCenter: NSPoint(x: bounds.width - radius, y: h - radius),
            radius: radius,
            startAngle: 0,
            endAngle: 90
        )
        path.line(to: NSPoint(x: radius, y: h))
        path.appendArc(
            withCenter: NSPoint(x: radius, y: h - radius),
            radius: radius,
            startAngle: 90,
            endAngle: 180
        )
        path.close()
        NotoDesign.NotchPalette.surface.setFill()
        path.fill()
        drawGrabber(in: bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !usesExpandedShape {
            if hasPhysicalNotch {
                let bandRect = NSRect(x: 0, y: 0, width: bounds.width, height: min(bandHeight, bounds.height))
                let bandPath = NSBezierPath(rect: bandRect)
                NotoDesign.NotchPalette.surface.setFill()
                bandPath.fill()
                drawGrabber(in: bounds)
            } else {
                drawCollapsedPill(in: bounds)
            }
            return
        }

        let radius = min(bottomRadius, bounds.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 0))
        path.line(to: NSPoint(x: bounds.width, y: 0))
        if bounds.height <= bandHeight + 2 {
            path.line(to: NSPoint(x: bounds.width, y: bounds.height))
            path.line(to: NSPoint(x: 0, y: bounds.height))
        } else {
            path.line(to: NSPoint(x: bounds.width, y: bounds.height - radius))
            path.appendArc(
                withCenter: NSPoint(x: bounds.width - radius, y: bounds.height - radius),
                radius: radius,
                startAngle: 0,
                endAngle: 90
            )
            path.line(to: NSPoint(x: radius, y: bounds.height))
            path.appendArc(
                withCenter: NSPoint(x: radius, y: bounds.height - radius),
                radius: radius,
                startAngle: 90,
                endAngle: 180
            )
        }
        path.close()

        if usesExpandedShape {
            NSColor.black.withAlphaComponent(0.22).setFill()
            path.fill()
        } else {
            NotoDesign.NotchPalette.surface.setFill()
            path.fill()
        }

        if bounds.height > bandHeight + 4 {
            NotoDesign.NotchPalette.stroke.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        drawGrabber(in: bounds)
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

final class NotchHoverController: NSObject {
    private weak var config: NotifConfig?
    private var panel: NotchOverlayPanel?
    private var rootView: NotchIslandRootView?
    private var hideTimer: Timer?
    private var hoverSyncTimer: Timer?
    private var events: [NotoEvent] = []
    private var eventIndex = 0
    private var isExpanded = false
    private var isAnimating = false
    private enum NotchAnimation { case expand, collapse }
    private var activeAnimation: NotchAnimation?
    private var geometry = NotchGeometry.current()
    private let panelModel = NotchPanelModel()
    private var panelContentMounted = false
    private var floatingTodoPanel: NSPanel?
    private var floatingNotesPanel: NSPanel?
    private let floatingTodoWindowDelegate = NotchFloatingWindowDelegate()
    private let floatingNotesWindowDelegate = NotchFloatingWindowDelegate()
    var onOpenApp: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var expandedContentHeight: CGFloat {
        NotoDesign.NotchLayout.expandedContentHeight(
            page: panelModel.selectedPage,
            todoMetrics: panelModel.todoStore.layoutMetrics,
            todoDoneExpanded: panelModel.todoStore.doneSectionExpanded,
            notesMetrics: panelModel.notesStore.layoutMetrics,
            showsFooter: panelModel.selectedPage == .notifications,
            isTodoPreview: panelModel.selectedPage == .todo && panelModel.isTodoDetached,
            isNotesPreview: panelModel.selectedPage == .notes && panelModel.isNotesDetached
        )
    }

    private var collapsedHeight: CGFloat { geometry.bandHeight }
    private var collapsedFrameHeight: CGFloat { collapsedHeight }
    private var expandedHeight: CGFloat { geometry.bandHeight + expandedContentHeight }
    private var collapsedWidth: CGFloat { geometry.collapsedWidth }
    private var expandedWidth: CGFloat { geometry.expandedWidth }

    private func syncRootMetrics() {
        rootView?.bandHeight = collapsedHeight
        rootView?.contentHeight = expandedContentHeight
        rootView?.showsExpandedBody = isExpanded
        rootView?.hasPhysicalNotch = geometry.hasPhysicalNotch
        rootView?.needsDisplay = true
        rootView?.needsLayout = true
    }

    /// Same level used by notch-kit / Dynamic Island clones — above the menu bar, not demoted.
    private let notchWindowLevel = NSWindow.Level.mainMenu + 3

    private func syncKeyboardInput() {
        guard let panel else { return }
        let editingPage = panelModel.selectedPage == .todo || panelModel.selectedPage == .notes
        let enable = isExpanded && editingPage && !panelModel.isContentDetached
        panel.keyboardInputEnabled = enable
        if enable {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func syncFloatingTodoFrame(reposition: Bool = false) {
        guard panelModel.isTodoDetached, let floatingTodoPanel else { return }
        let height = NotoDesign.NotchLayout.todoFloatingHeight(
            metrics: panelModel.todoStore.layoutMetrics,
            doneExpanded: panelModel.todoStore.doneSectionExpanded
        )
        let width: CGFloat = 300

        if reposition {
            floatingTodoPanel.setFrame(floatingTodoFrame(height: height), display: true)
            return
        }

        var frame = floatingTodoPanel.frame
        guard abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 else { return }

        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        floatingTodoPanel.setFrame(frame, display: true, animate: false)
    }

    private func floatingTodoFrame(height: CGFloat) -> NSRect {
        let width: CGFloat = 300
        if let panel {
            let anchor = panel.frame
            let x = anchor.midX - width / 2
            let y = anchor.minY - height - 10
            return NSRect(x: x, y: y, width: width, height: height)
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - width / 2, y: mouse.y - height - 20, width: width, height: height)
    }

    private func showFloatingTodoPreview() {
        let height = NotoDesign.NotchLayout.todoFloatingHeight(
            metrics: panelModel.todoStore.layoutMetrics,
            doneExpanded: panelModel.todoStore.doneSectionExpanded
        )

        if floatingTodoPanel == nil {
            let panel = NSPanel(
                contentRect: floatingTodoFrame(height: height),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            floatingTodoWindowDelegate.onClose = { [weak self] in
                self?.attachTodoToNotch()
            }
            panel.delegate = floatingTodoWindowDelegate
            floatingTodoPanel = panel
        }

        floatingTodoPanel?.contentView = NSHostingView(
            rootView: NotchTodoFloatingContent(
                store: panelModel.todoStore,
                onAttach: { [weak self] in self?.attachTodoToNotch() }
            )
        )
        floatingTodoPanel?.setFrame(floatingTodoFrame(height: height), display: true)
        floatingTodoPanel?.orderFrontRegardless()
    }

    private func closeFloatingTodoPreview() {
        floatingTodoPanel?.orderOut(nil)
    }

    private func handleDetachTodo() {
        guard panelModel.selectedPage == .todo, !panelModel.isTodoDetached else { return }
        panelModel.isTodoDetached = true
        panelModel.isPinned = false
        hideTimer?.invalidate()
        showFloatingTodoPreview()
        if isExpanded || isAnimating {
            collapsePanel()
        } else {
            syncFloatingTodoFrame(reposition: true)
            floatingTodoPanel?.orderFrontRegardless()
        }
    }

    private func attachTodoToNotch() {
        guard panelModel.isTodoDetached else { return }
        panelModel.isTodoDetached = false
        closeFloatingTodoPreview()
        panelModel.selectedPage = .todo
        syncPanelForCurrentPage()
        if isEnabled, interactionRect().contains(NSEvent.mouseLocation) {
            expandPanel(autoHideAfter: 30.0)
        }
    }

    private func syncFloatingNotesFrame(reposition: Bool = false) {
        guard panelModel.isNotesDetached, let floatingNotesPanel else { return }
        let height = NotoDesign.NotchLayout.notesFloatingHeight(metrics: panelModel.notesStore.layoutMetrics)
        let width = NotoDesign.NotchLayout.notesFloatingWidth

        if reposition {
            floatingNotesPanel.setFrame(floatingNotesFrame(height: height), display: true)
            return
        }

        var frame = floatingNotesPanel.frame
        guard abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 else { return }

        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        floatingNotesPanel.setFrame(frame, display: true, animate: false)
    }

    private func floatingNotesFrame(height: CGFloat) -> NSRect {
        let width = NotoDesign.NotchLayout.notesFloatingWidth
        if let panel {
            let anchor = panel.frame
            let x = anchor.midX - width / 2
            let y = anchor.minY - height - 10
            return NSRect(x: x, y: y, width: width, height: height)
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - width / 2, y: mouse.y - height - 20, width: width, height: height)
    }

    private func showFloatingNotes() {
        let height = NotoDesign.NotchLayout.notesFloatingHeight(metrics: panelModel.notesStore.layoutMetrics)

        if floatingNotesPanel == nil {
            let panel = NotchFloatingEditPanel(
                contentRect: floatingNotesFrame(height: height),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            floatingNotesWindowDelegate.onClose = { [weak self] in
                self?.attachNotesToNotch()
            }
            panel.delegate = floatingNotesWindowDelegate
            floatingNotesPanel = panel
        }

        floatingNotesPanel?.contentView = NSHostingView(
            rootView: NotchNotesFloatingContent(
                store: panelModel.notesStore,
                onAttach: { [weak self] in self?.attachNotesToNotch() },
                onActivity: { [weak self] in
                    self?.syncPanelForCurrentPage()
                    self?.syncFloatingNotesFrame()
                },
                onBeginEditing: { [weak self] in
                    NSApp.activate(ignoringOtherApps: true)
                    self?.floatingNotesPanel?.makeKeyAndOrderFront(nil)
                }
            )
        )
        floatingNotesPanel?.setFrame(floatingNotesFrame(height: height), display: true)
        floatingNotesPanel?.orderFrontRegardless()
    }

    private func closeFloatingNotes() {
        floatingNotesPanel?.orderOut(nil)
    }

    private func handleDetachNotes() {
        guard panelModel.selectedPage == .notes, !panelModel.isNotesDetached else { return }
        panelModel.isNotesDetached = true
        panelModel.isPinned = false
        hideTimer?.invalidate()
        showFloatingNotes()
        if isExpanded || isAnimating {
            collapsePanel()
        } else {
            syncFloatingNotesFrame(reposition: true)
            floatingNotesPanel?.orderFrontRegardless()
        }
    }

    private func attachNotesToNotch() {
        guard panelModel.isNotesDetached else { return }
        panelModel.isNotesDetached = false
        closeFloatingNotes()
        panelModel.selectedPage = .notes
        syncPanelForCurrentPage()
        if isEnabled, interactionRect().contains(NSEvent.mouseLocation) {
            expandPanel(autoHideAfter: 30.0)
        }
    }

    private func syncPanelForCurrentPage() {
        syncKeyboardInput()
        syncRootMetrics()
        guard isExpanded, let panel else { return }
        panel.setFrame(panelFrame(height: expandedHeight, width: expandedWidth), display: true, animate: true)
    }

    private func bringPanelToFront() {
        guard let panel else { return }
        panel.level = notchWindowLevel
        panel.orderFrontRegardless()
        panel.level = notchWindowLevel
    }

    init(config: NotifConfig) {
        self.config = config
        super.init()
        panelModel.todoStore.onItemsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.syncPanelForCurrentPage()
                self?.syncFloatingTodoFrame()
            }
        }
        panelModel.notesStore.onPagesChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.syncPanelForCurrentPage()
                self?.syncFloatingNotesFrame()
            }
        }
    }

    func start() {
        reloadEvents()
        setupPanel()
        startHoverSync()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        hideTimer?.invalidate()
        hoverSyncTimer?.invalidate()
        hoverSyncTimer = nil
        closeFloatingTodoPreview()
        closeFloatingNotes()
        panelModel.isTodoDetached = false
        panelModel.isNotesDetached = false
        panel?.orderOut(nil)
    }

    func flashLatestEvent() {
        guard isEnabled else { return }
        reloadEvents()
        eventIndex = 0
        panelModel.selectedPage = .notifications
        expandPanel(autoHideAfter: 4.0)
    }

    func refreshEnabledState() {
        if isEnabled {
            startHoverSync()
            showCollapsedIdle()
        } else {
            hoverSyncTimer?.invalidate()
            hoverSyncTimer = nil
            hidePanel(immediate: true)
        }
    }

    private var isEnabled: Bool {
        config?.notchPreviewEnabled ?? true
    }

    private func reloadEvents() {
        events = Array(NotoEventLog.load().filter { $0.delivered }.prefix(5))
        if eventIndex >= events.count {
            eventIndex = 0
        }
    }

    @objc private func screenChanged() {
        geometry = NotchGeometry.current()
        repositionPanel()
    }

    private func setupPanel() {
        geometry = NotchGeometry.current()
        let initial = panelFrame(height: collapsedFrameHeight, width: collapsedWidth)
        let panel = NotchOverlayPanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: geometry.screen
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = false
        panel.level = notchWindowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        let root = NotchIslandRootView(onEnter: {}, onExit: {})
        root.autoresizingMask = [.width, .height]
        panel.contentView = root
        self.panel = panel
        self.rootView = root
        syncRootMetrics()
        updatePanelContent()
        showCollapsedIdle()
    }

    private func showCollapsedIdle() {
        guard isEnabled, let panel else { return }
        isExpanded = false
        isAnimating = false
        activeAnimation = nil
        geometry = NotchGeometry.current()
        syncRootMetrics()
        applyPanelFrame(height: collapsedFrameHeight, width: collapsedWidth, animate: false)
        panel.alphaValue = 1
        bringPanelToFront()
    }

    private func startHoverSync() {
        hoverSyncTimer?.invalidate()
        hoverSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncHoverState()
            }
        }
    }

    private func interactionRect() -> NSRect {
        if isExpanded || isAnimating {
            return panelFrame(height: expandedHeight, width: expandedWidth)
        }
        return panelFrame(height: collapsedFrameHeight, width: collapsedWidth)
    }

    private func syncHoverState() {
        guard isEnabled else { return }
        let inside = interactionRect().contains(NSEvent.mouseLocation)
        if inside {
            hideTimer?.invalidate()
            if panelModel.isContentDetached {
                return
            }
            if !isExpanded && !isAnimating {
                reloadEvents()
                expandPanel(autoHideAfter: nil)
            }
        } else if (isExpanded || isAnimating) && activeAnimation != .collapse {
            if panelModel.isPinned {
                return
            }
            collapsePanel()
        }
    }

    private func expandPanel(autoHideAfter: TimeInterval?) {
        guard isEnabled, let panel, !isExpanded, !isAnimating else { return }
        activeAnimation = .expand
        isAnimating = true
        isExpanded = true
        geometry = NotchGeometry.current()
        syncRootMetrics()
        updatePanelContent()
        rootView?.prepareContentHidden()
        panel.alphaValue = 1
        bringPanelToFront()
        rootView?.beginContinuousRedraw()
        applyPanelFrame(height: expandedHeight, width: expandedWidth, animate: true, duration: 0.30) { [weak self] in
            guard let self, self.activeAnimation == .expand else { return }
            self.isAnimating = false
            self.activeAnimation = nil
            self.rootView?.setContentAlpha(1, animated: false)
            self.rootView?.endContinuousRedraw()
            self.syncPanelForCurrentPage()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.isExpanded else { return }
            self.rootView?.setContentAlpha(1, animated: true, duration: 0.20)
        }
        if let delay = autoHideAfter {
            scheduleHide(after: delay)
        }
    }

    private func repositionPanel() {
        geometry = NotchGeometry.current()
        guard let panel, panel.isVisible else { return }
        if isExpanded {
            panel.setFrame(panelFrame(height: expandedHeight, width: expandedWidth), display: true)
        } else {
            panel.setFrame(panelFrame(height: collapsedFrameHeight, width: collapsedWidth), display: true)
        }
    }

    private func panelFrame(height: CGFloat, width: CGFloat) -> NSRect {
        let screenFrame = geometry.screen.frame
        let x = geometry.notchCenterX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyPanelFrame(
        height: CGFloat,
        width: CGFloat,
        animate: Bool,
        duration: TimeInterval = 0.30,
        timing: CAMediaTimingFunction? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard let panel else {
            completion?()
            return
        }
        let target = panelFrame(height: height, width: width)
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = timing ?? CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                self?.rootView?.needsDisplay = true
                self?.rootView?.layoutSubtreeIfNeeded()
                completion?()
            }
        } else {
            panel.setFrame(target, display: true)
            rootView?.needsDisplay = true
            completion?()
        }
    }

    private func collapsePanel() {
        guard panel != nil, isExpanded || activeAnimation == .expand else { return }
        hideTimer?.invalidate()
        activeAnimation = .collapse
        isAnimating = true

        rootView?.setContentAlpha(0, animated: true, duration: 0.14)

        let collapseTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        rootView?.beginContinuousRedraw()
        applyPanelFrame(
            height: collapsedFrameHeight,
            width: collapsedWidth,
            animate: true,
            duration: 0.30,
            timing: collapseTiming
        ) { [weak self] in
            guard let self, self.activeAnimation == .collapse else { return }
            self.isExpanded = false
            self.isAnimating = false
            self.activeAnimation = nil
            self.panelModel.isPinned = false
            self.geometry = NotchGeometry.current()
            self.syncRootMetrics()
            self.panel?.keyboardInputEnabled = false
            self.rootView?.prepareContentHidden()
            self.rootView?.endContinuousRedraw()
            if self.panelModel.isTodoDetached {
                self.syncFloatingTodoFrame(reposition: true)
                self.floatingTodoPanel?.orderFrontRegardless()
            }
            if self.panelModel.isNotesDetached {
                self.syncFloatingNotesFrame(reposition: true)
                self.floatingNotesPanel?.orderFrontRegardless()
            }
        }
    }

    private func hidePanel(immediate: Bool) {
        hideTimer?.invalidate()
        guard let panel else { return }
        if immediate {
            isExpanded = false
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }
        collapsePanel()
    }

    private func scheduleHide(after delay: TimeInterval) {
        guard !panelModel.isPinned else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapsePanel()
            }
        }
    }

    private func handlePinToggle(_ pinned: Bool) {
        if pinned {
            hideTimer?.invalidate()
            syncKeyboardInput()
        } else if isExpanded, !interactionRect().contains(NSEvent.mouseLocation) {
            collapsePanel()
        }
    }

    private func updatePanelContent() {
        guard let rootView else { return }
        panelModel.events = events
        panelModel.eventIndex = eventIndex
        panelModel.todoStore.refreshDayIfNeeded()

        if !panelContentMounted {
            rootView.mount(NotchPanelContent(
                model: panelModel,
                showsOpenButton: true,
                onSelectPage: { [weak self] page in
                    guard let self else { return }
                    self.panelModel.selectedPage = page
                    self.syncPanelForCurrentPage()
                    let hideDelay: TimeInterval = (page == .todo || page == .notes) ? 30.0 : 4.0
                    self.scheduleHide(after: hideDelay)
                },
                onPrevious: { [weak self] in self?.stepEvent(-1) },
                onNext: { [weak self] in self?.stepEvent(1) },
                onOpenSettings: { [weak self] in self?.onOpenSettings?() },
                onOpen: { [weak self] in self?.openCurrentApp() },
                onActivity: { [weak self] in
                    self?.syncPanelForCurrentPage()
                    self?.scheduleHide(after: 30.0)
                },
                onBeginEditing: { [weak self] in
                    self?.syncKeyboardInput()
                    self?.scheduleHide(after: 30.0)
                },
                onPinToggle: { [weak self] pinned in
                    self?.handlePinToggle(pinned)
                },
                onDetachTodo: { [weak self] in
                    self?.handleDetachTodo()
                },
                onDetachNotes: { [weak self] in
                    self?.handleDetachNotes()
                },
                onAttachNotes: { [weak self] in
                    self?.attachNotesToNotch()
                }
            ))
            panelContentMounted = true
        }
    }

    private func openCurrentApp() {
        let event = panelModel.currentEvent
        let app = event?.openApp
            ?? NotifProfile.allCases.first(where: { $0.label == event?.profile })?.openAppName
            ?? NotifProfile.cursor.openAppName
        onOpenApp?(app)
    }

    private func stepEvent(_ delta: Int) {
        guard !events.isEmpty else { return }
        eventIndex = (eventIndex + delta + events.count) % events.count
        updatePanelContent()
        scheduleHide(after: 4.0)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    let config = NotifConfig()
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?

    private static let pidFile = "/tmp/noto-menubar.pid"
    private static let queueFiles = [
        "/tmp/noto-claude-pending.json",
        "/tmp/noto-cursor-pending.json",
        "/tmp/noto-codex-pending.json",
        // Legacy queue paths — cleaned up during transition
        "/tmp/claude-notif-pending.json",
        "/tmp/cursor-notif-pending.json",
        "/tmp/codex-notif-pending.json",
    ]
    private static let coalesceDelay: TimeInterval = 1.5
    private var signalSource: DispatchSourceSignal?
    private var pendingDoneNotifications: [PendingNotification] = []
    private var coalesceWorkItem: DispatchWorkItem?
    private var snoozeMenuItem: NSMenuItem?
    private var resumeMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var snoozeRefreshTimer: Timer?
    private var notchController: NotchHoverController?

    func applicationDidFinishLaunching(_ note: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let args = CommandLine.arguments
        if args.contains("--title") || args.contains("--message") {
            sendNotification(args: args)
        } else {
            if anotherInstanceIsRunning() {
                NSApp.terminate(nil)
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            setupMenuBar()
            writePidFile()
            setupSignalHandler()
            MacFocusMonitor.startPolling()
            notchController = NotchHoverController(config: config)
            notchController?.onOpenApp = { [weak self] app in self?.activateApp(named: app) }
            notchController?.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
            notchController?.start()
            refreshSnoozeMenuItem()
            scheduleSnoozeRefresh()
            showSettingsWindow()
        }
    }

    private func anotherInstanceIsRunning() -> Bool {
        let myPid = ProcessInfo.processInfo.processIdentifier
        guard let raw = try? String(contentsOfFile: AppDelegate.pidFile, encoding: .utf8),
              let existing = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              existing != myPid,
              kill(existing, 0) == 0
        else { return false }

        // Another instance is already running — ask it to show settings.
        kill(existing, SIGUSR2)
        return true
    }

    // MARK: PID file + SIGUSR1 handler

    private func writePidFile() {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        try? pid.write(toFile: AppDelegate.pidFile, atomically: true, encoding: .utf8)
    }

    private func setupSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)

        let notifSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        notifSrc.setEventHandler { [weak self] in self?.postQueuedNotification() }
        notifSrc.resume()

        let settingsSrc = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        settingsSrc.setEventHandler { [weak self] in self?.showSettingsWindow() }
        settingsSrc.resume()

        signalSource = notifSrc
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    private func postQueuedNotification() {
        config.reloadFromDisk()
        guard config.enabled else { return }
        guard !NotoSnooze.isActive() else { return }
        MacFocusMonitor.refresh()

        for queuePath in Self.queueFiles {
            guard FileManager.default.fileExists(atPath: queuePath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: queuePath)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let item = PendingNotification(json)
            else { continue }

            try? FileManager.default.removeItem(atPath: queuePath)
            ingestNotification(item)
        }
    }

    private func ingestNotification(_ item: PendingNotification, immediate: Bool = false) {
        guard config.settings(for: item.profile).enabled else { return }

        if let reason = suppressReason(for: item) {
            NotoEventLog.record(item, delivered: false, reason: reason)
            return
        }

        if immediate || item.kind != "done" {
            deliverNotification(item)
            return
        }

        pendingDoneNotifications.append(item)
        coalesceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingDoneNotifications()
        }
        coalesceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceDelay, execute: work)
    }

    private func suppressReason(for item: PendingNotification) -> String? {
        if NotoSnooze.isActive() { return "Snoozed" }
        if config.respectMacFocus && MacFocusMonitor.isActive() { return "macOS Focus" }
        if config.focusMode == .deepWork && item.kind != "done" { return "Deep Work" }
        if config.focusMode == .deepWork && !config.settings(for: item.profile).enableDone {
            return "Deep Work"
        }
        return nil
    }

    private func flushPendingDoneNotifications() {
        let batch = pendingDoneNotifications
        pendingDoneNotifications = []
        guard !batch.isEmpty else { return }

        if batch.count == 1 {
            deliverNotification(batch[0])
            return
        }

        let labels = Array(Set(batch.map { $0.profile.label })).sorted()
        let lines = batch.prefix(3).map { "\($0.profile.label): \($0.body)" }
        let combined = PendingNotification(
            profile: batch[0].profile,
            title: "Noto",
            subtitle: "\(batch.count) finished · \(labels.joined(separator: ", "))",
            body: lines.joined(separator: "\n"),
            sound: batch[0].sound,
            volume: batch[0].volume,
            openApp: batch[0].openApp,
            kind: "done"
        )
        deliverNotification(combined)
    }

    private func deliverNotification(_ item: PendingNotification) {
        guard config.enabled else { return }
        guard config.settings(for: item.profile).enabled else { return }
        if let reason = suppressReason(for: item) {
            NotoEventLog.record(item, delivered: false, reason: reason)
            return
        }

        let displayTitle = item.title.isEmpty ? config.settings(for: item.profile).titlePrefix : item.title
        if !item.sound.isEmpty { playSound(item.sound, volume: item.volume) }

        let content = UNMutableNotificationContent()
        content.title = displayTitle
        if !item.subtitle.isEmpty { content.subtitle = item.subtitle }
        content.body = item.body
        content.categoryIdentifier = categoryIdentifier(for: item.profile)
        content.userInfo = ["openApp": item.openApp]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
        NotoEventLog.record(item, delivered: true, resolvedTitle: displayTitle)
        DispatchQueue.main.async { [weak self] in
            self?.notchController?.flashLatestEvent()
        }
        rebuildMenuBar()
    }

    private func enqueueNotification(
        profile: NotifProfile,
        title: String,
        subtitle: String,
        body: String,
        sound: String,
        volume: Double,
        immediate: Bool = false
    ) {
        let item = PendingNotification(
            profile: profile,
            title: title,
            subtitle: subtitle,
            body: body,
            sound: sound,
            volume: volume,
            openApp: profile.openAppName,
            kind: immediate ? "alert" : "done"
        )
        ingestNotification(item, immediate: immediate)
    }

    func applicationWillTerminate(_ note: Notification) {
        notchController?.stop()
        try? FileManager.default.removeItem(atPath: AppDelegate.pidFile)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "SNOOZE_1H":
            NotoSnooze.set(minutes: 60)
            refreshSnoozeMenuItem()
            scheduleSnoozeRefresh()
        case let id where id.hasPrefix("OPEN_"):
            let openApp = response.notification.request.content.userInfo["openApp"] as? String
                ?? id.replacingOccurrences(of: "OPEN_", with: "")
            activateApp(named: openApp)
        default:
            break
        }
        completionHandler()
    }

    private func activateApp(named appName: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"\(appName)\" to activate"]
        try? p.run()
    }

    private func categoryIdentifier(for profile: NotifProfile) -> String {
        "NOTO_\(profile.rawValue.uppercased())"
    }

    // MARK: Notification mode

    private func sendNotification(args: [String]) {
        NSApp.setActivationPolicy(.accessory)
        // Hard deadline: always exit within 3s so the hook never blocks bash.
        // exit(0) is used throughout — NSApp.terminate(nil) is unreliable in
        // accessory/LSUIElement mode and can stall in the run loop indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { exit(0) }
        guard config.enabled else { exit(0) }

        var title = "Claude Code", subtitle = "", body = "Done."
        var sound = "", volume = 1.0
        var i = 1
        while i < args.count {
            let v = i + 1 < args.count ? args[i + 1] : ""
            switch args[i] {
            case "--title":    title    = v; i += 2
            case "--subtitle": subtitle = v; i += 2
            case "--message":  body     = v; i += 2
            case "--sound":    sound    = v; i += 2
            case "--volume":   volume   = Double(v) ?? 1.0; i += 2
            default:           i += 1
            }
        }

        if !sound.isEmpty { playSound(sound, volume: volume) }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { exit(0) }
            let content = UNMutableNotificationContent()
            content.title              = title
            if !subtitle.isEmpty { content.subtitle = subtitle }
            content.body               = body
            content.categoryIdentifier = "NOTO"
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil)) { _ in
                // Wait 1s so system sounds finish playing before we exit.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
            }
        }
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        var categories: [UNNotificationCategory] = []
        for profile in NotifProfile.allCases {
            let openAction = UNNotificationAction(
                identifier: "OPEN_\(profile.openAppName)",
                title: "Open \(profile.label)",
                options: [.foreground]
            )
            let snoozeAction = UNNotificationAction(
                identifier: "SNOOZE_1H",
                title: "Mute 1 hour",
                options: []
            )
            categories.append(UNNotificationCategory(
                identifier: categoryIdentifier(for: profile),
                actions: [openAction, snoozeAction],
                intentIdentifiers: [],
                options: []
            ))
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))

        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            let icon = NSApp.applicationIconImage.copy() as! NSImage
            icon.size = NSSize(width: 18, height: 18)
            btn.image = icon
        }

        rebuildMenuBar()
    }

    private func rebuildMenuBar() {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(title: "Enable Notifications", action: #selector(quickToggle), keyEquivalent: "")
        toggleItem.state = config.enabled ? .on : .off
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        menu.addItem(.separator())
        appendHistorySection(to: menu)
        menu.addItem(.separator())

        let snoozeItem = NSMenuItem(title: "Mute 1 hour", action: #selector(snoozeOneHour), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)
        snoozeMenuItem = snoozeItem

        let resumeItem = NSMenuItem(title: "Resume notifications", action: #selector(clearSnooze), keyEquivalent: "")
        resumeItem.target = self
        resumeItem.isHidden = true
        menu.addItem(resumeItem)
        resumeMenuItem = resumeItem

        refreshSnoozeMenuItem()

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuBarClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Noto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func appendHistorySection(to menu: NSMenu) {
        let events = NotoEventLog.load().filter { $0.delivered }

        let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if events.isEmpty {
            let empty = NSMenuItem(title: "No notifications yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for event in events.prefix(NotoEventLog.menuLimit) {
            let when = NotoEventLog.relativeTime(since: event.date)
            let line1 = "\(event.profile) · \(when)"
            let line2 = truncateForMenu(event.menuDetail, limit: 72)
            let item = NSMenuItem(
                title: line2.isEmpty ? line1 : "\(line1)\n\(line2)",
                action: #selector(openFromHistory(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = event.openApp ?? profileOpenApp(for: event.profile)
            item.toolTip = event.menuDetail
            menu.addItem(item)
        }

        if !events.isEmpty {
            menu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    private func profileOpenApp(for label: String) -> String {
        NotifProfile.allCases.first(where: { $0.label == label })?.openAppName ?? label
    }

    private func truncateForMenu(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenuBar()
    }

    @objc private func openFromHistory(_ sender: NSMenuItem) {
        guard let openApp = sender.representedObject as? String, !openApp.isEmpty else { return }
        activateApp(named: openApp)
    }

    @objc private func clearHistory() {
        NotoEventLog.clear()
        rebuildMenuBar()
    }

    // Menu bar quick toggle saves immediately — it's outside the settings window
    @objc private func quickToggle() {
        config.enabled.toggle()
        config.save()
        toggleMenuItem?.state = config.enabled ? .on : .off
    }

    @objc private func snoozeOneHour() {
        NotoSnooze.set(minutes: 60)
        refreshSnoozeMenuItem()
        scheduleSnoozeRefresh()
    }

    @objc private func clearSnooze() {
        NotoSnooze.clear()
        refreshSnoozeMenuItem()
    }

    private func refreshSnoozeMenuItem() {
        if let until = NotoSnooze.untilDate() {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            snoozeMenuItem?.title = "Snoozed until \(formatter.string(from: until))"
            snoozeMenuItem?.isEnabled = false
            resumeMenuItem?.isHidden = false
        } else {
            snoozeMenuItem?.title = "Mute 1 hour"
            snoozeMenuItem?.isEnabled = true
            resumeMenuItem?.isHidden = true
        }
    }

    private func scheduleSnoozeRefresh() {
        snoozeRefreshTimer?.invalidate()
        guard let until = NotoSnooze.untilDate() else { return }
        let interval = until.timeIntervalSinceNow + 0.5
        guard interval > 0 else {
            refreshSnoozeMenuItem()
            return
        }
        snoozeRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            NotoSnooze.clear()
            self?.refreshSnoozeMenuItem()
        }
    }

    @objc private func menuBarClicked() {
        showSettingsWindow()
    }

    // MARK: Settings window

    func showSettingsWindow() {
        if let win = settingsWindow {
            win.title = "Noto"
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: NotoDesign.settingsWidth, height: NotoDesign.settingsHeight),
            styleMask:   [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        win.titlebarAppearsTransparent = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.minSize = NSSize(width: NotoDesign.settingsWidth, height: NotoDesign.settingsHeight)
        win.contentView = NSHostingView(rootView: SettingsView(config: config, onPinToggle: { [weak win] pinned in
            win?.level = pinned ? .floating : .normal
        }, onSendTest: { [weak self] profile in
            self?.sendTest(for: profile)
        }, onNotchSettingsChanged: { [weak self] in
            DispatchQueue.main.async {
                self?.notchController?.refreshEnabledState()
            }
        }))
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("NotoSettings1")
        win.title = "Noto"
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    private func sendTest(for profile: NotifProfile) {
        guard config.settings(for: profile).enabled else { return }
        config.save()

        let settings = config.settings(for: profile)
        let prefix = settings.titlePrefix.isEmpty ? profile.defaultTitle : settings.titlePrefix
        let sample = kPreviewSample
        let body = ProfileSettings.previewBodyLikeHook(from: sample, mode: settings.previewLength)

        enqueueNotification(
            profile: profile,
            title: prefix,
            subtitle: NotoNotificationDisplay.sampleSubtitle(for: profile),
            body: body,
            sound: settings.soundDone,
            volume: settings.volumeDone,
            immediate: true
        )
    }
}

// MARK: - Entry Point

@main
struct NotoEntry {
    static func main() {
        let app      = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Settings View

private let kPreviewSample = "Noto is working. This is the second sentence you should see. This third sentence only appears in Full preview mode."

private let kSounds = ["Ping", "Basso", "Pop", "Funk", "Glass", "Hero",
                       "Morse", "Bottle", "Frog", "Blow", "Purr", "Sosumi",
                       "Submarine", "Tink"]

private enum UpdateStatus: Equatable {
    case idle, checking, upToDate, available(String), updating, failed
    var label: String {
        switch self {
        case .idle:              return "Check for Update"
        case .checking:          return "Checking…"
        case .upToDate:          return "Up to date"
        case .available(let v):  return "Update to v\(v)"
        case .updating:          return "Updating…"
        case .failed:            return "Check failed"
        }
    }
    var isSpinning: Bool { self == .checking || self == .updating }
    var isDisabled: Bool { self == .checking || self == .updating }
}

struct SettingsView: View {
    @ObservedObject var config: NotifConfig
    @State private var isPinned = false
    @State private var selectedProfile: NotifProfile = .cursor
    @State private var updateStatus: UpdateStatus = .idle
    @State private var hookHealth: [HookHealthStatus] = HookHealthChecker.statuses()
    @State private var notifierRunning = HookHealthChecker.notifierRunning()
    @State private var macFocusActive = MacFocusMonitor.isActive()
    @State private var recentEvents: [NotoEvent] = NotoEventLog.load()
    var onPinToggle: (Bool) -> Void = { _ in }
    var onSendTest: (NotifProfile) -> Void = { _ in }
    var onNotchSettingsChanged: () -> Void = {}

    private var currentSettings: ProfileSettings {
        config.settings(for: selectedProfile)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var saveStatusFooter: String {
        switch config.saveState {
        case .saved:
            return "Saved. Live notifications use these settings."
        case .saving:
            return "Saving…"
        }
    }

    var body: some View {
        Form {
                Section {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Noto")
                                .font(.headline)
                            Text("Agent notifications")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            isPinned.toggle()
                            onPinToggle(isPinned)
                        } label: {
                            NotoSymbol(name: isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(isPinned ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isPinned ? "Unpin window" : "Keep window on top")
                        Toggle("Enabled", isOn: $config.enabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                Section("Platform") {
                    Picker("Focus mode", selection: $config.focusMode) {
                        ForEach(NotifFocusMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!config.enabled)

                    Toggle("Respect macOS Focus", isOn: $config.respectMacFocus)
                        .disabled(!config.enabled)

                    Toggle("Notch hover preview", isOn: $config.notchPreviewEnabled)
                        .disabled(!config.enabled)

                    if macFocusActive && config.respectMacFocus && config.enabled {
                        Label("macOS Focus is active", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(NotifProfile.allCases) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!config.enabled)
                }

                Section("Notch Todo") {
                    NotchTodoSettingsPanel()
                }

                if config.enabled {
                    Section("Live Preview") {
                        NotificationPreviewCard(
                            profile: selectedProfile,
                            settings: currentSettings
                        )
                    }

                    ProfileSettingsForm(
                        settings: config.binding(for: selectedProfile),
                        profile: selectedProfile
                    )

                    Section {
                        EventTimelinePanel(events: recentEvents)
                    }
                } else {
                    Section {
                        Text("Turn on Noto to configure profiles.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                }

                Section {
                    Button("Send Test Notification") {
                        onSendTest(selectedProfile)
                    }
                    .disabled(!config.enabled || !config.settings(for: selectedProfile).enabled)
                } footer: {
                    Text(saveStatusFooter)
                }

                Section("Status") {
                    LabeledContent("Noto") {
                        Text(notifierRunning ? "Running" : "Not running")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(hookHealth, id: \.profile) { status in
                        LabeledContent(status.profile.label) {
                            Text(status.hookInstalled ? "Ready" : "Hook not installed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if config.focusMode != .available {
                        LabeledContent("Focus mode") {
                            Text(config.focusMode.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if macFocusActive {
                        LabeledContent("macOS Focus") {
                            Text("Active")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    if updateStatus.isSpinning {
                        LabeledContent("Updates") {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Button(updateStatus.label) {
                            checkForUpdate()
                        }
                        .disabled(updateStatus.isDisabled)
                    }
                } footer: {
                    Text("Developed by Teevo Joel")
                }
        }
        .formStyle(.grouped)
        .frame(width: NotoDesign.settingsWidth, height: NotoDesign.settingsHeight)
        .onChange(of: config.enabled) { _, _ in config.scheduleAutoSave() }
        .onChange(of: config.focusMode) { _, _ in config.scheduleAutoSave() }
        .onChange(of: config.respectMacFocus) { _, _ in config.scheduleAutoSave() }
        .onChange(of: config.notchPreviewEnabled) { _, _ in
            config.scheduleAutoSave()
            onNotchSettingsChanged()
        }
        .onChange(of: config.claude) { _, _ in config.scheduleAutoSave() }
        .onChange(of: config.cursor) { _, _ in config.scheduleAutoSave() }
        .onChange(of: config.codex) { _, _ in config.scheduleAutoSave() }
        .onAppear { refreshStatus() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        MacFocusMonitor.refresh()
        hookHealth = HookHealthChecker.statuses()
        notifierRunning = HookHealthChecker.notifierRunning()
        macFocusActive = MacFocusMonitor.isActive()
        recentEvents = NotoEventLog.load()
    }

    private func checkForUpdate() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        updateStatus = .checking
        URLSession.shared.dataTask(with: URL(string: "https://registry.npmjs.org/noto/latest")!) { data, _, _ in
            DispatchQueue.main.async {
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latest = json["version"] as? String
                else { updateStatus = .failed; return }

                if latest == current {
                    updateStatus = .upToDate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updateStatus = .idle }
                } else {
                    updateStatus = .available(latest)
                    runUpdate(version: latest)
                }
            }
        }.resume()
    }

    private func runUpdate(version: String) {
        updateStatus = .updating
        DispatchQueue.global(qos: .utility).async {
            let script = (NSHomeDirectory() as NSString).appendingPathComponent(".noto/updater.sh")
            let p = Process()
            if FileManager.default.fileExists(atPath: script) {
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script]
            } else {
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", "npx --yes noto@\(version) --update"]
            }
            p.environment = ProcessInfo.processInfo.environment
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                if p.terminationStatus == 0 {
                    updateStatus = .upToDate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updateStatus = .idle }
                } else {
                    updateStatus = .failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updateStatus = .idle }
                }
            }
        }
    }
}

// MARK: - Live Preview + Hook Health

struct NotificationPreviewCard: View {
    let profile: NotifProfile
    let settings: ProfileSettings

    private var display: NotoNotificationDisplay {
        .preview(for: profile, settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Profile") {
                Text(display.profile.label)
            }
            if !display.subtitle.isEmpty {
                LabeledContent("Context") {
                    Text(display.subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Title") {
                Text(display.title)
            }
            if let sound = display.sound {
                LabeledContent("Sound") {
                    Text(sound)
                        .foregroundStyle(.secondary)
                }
            }
            Text(display.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .opacity(settings.enabled ? 1 : 0.45)
    }
}

struct HookHealthStatus: Equatable {
    let profile: NotifProfile
    let hookInstalled: Bool
}

enum HookHealthChecker {
    static func statuses() -> [HookHealthStatus] {
        NotifProfile.allCases.map { profile in
            HookHealthStatus(
                profile: profile,
                hookInstalled: FileManager.default.isExecutableFile(atPath: profile.hookScriptPath)
            )
        }
    }

    static func notifierRunning() -> Bool {
        guard let raw = try? String(contentsOfFile: "/tmp/noto-menubar.pid", encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else { return false }
        return kill(pid, 0) == 0
    }
}

struct EventTimelinePanel: View {
    let events: [NotoEvent]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if events.isEmpty {
                Text("No recent notifications yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(10)) { event in
                    EventTimelineRow(event: event)
                }
            }
        } label: {
            HStack {
                Text("Recent activity")
                Spacer()
                Text("\(events.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EventTimelineRow: View {
    let event: NotoEvent

    private var kindLabel: String {
        switch event.kind {
        case "done": return "Done"
        case "alert": return "Alert"
        case "longrun": return "Long run"
        case "approval": return "Approval"
        default: return event.kind.capitalized
        }
    }

    var body: some View {
        LabeledContent {
            Text(NotoEventLog.relativeTime(since: event.date))
                .foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.profile)
                        .fontWeight(.medium)
                    Text(kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !event.delivered {
                        Text("Suppressed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(event.suppressReason ?? "Suppressed")
                    }
                }
                Text(event.title.isEmpty ? event.body : event.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Todo Settings Panel

private struct NotchTodoSettingsPanel: View {
    @ObservedObject private var store = NotchDailyTodoStore.shared

    private let hubUsers = ["joel", "cyrus", "irene", "kiki", "alex", "nikita", "ferdy"]

    var body: some View {
        Toggle("Roll unfinished to next day", isOn: $store.prefs.autoRollUnfinished)
            .onChange(of: store.prefs.autoRollUnfinished) { _, _ in store.savePrefsAndHub() }

        LabeledContent("Templates") {
            Text("\(store.templates.count) saved")
                .foregroundStyle(.secondary)
        }

        Toggle("Sync Teevo Hub todos", isOn: $store.hub.enabled)
            .onChange(of: store.hub.enabled) { _, _ in
                store.savePrefsAndHub()
                if store.hub.enabled { store.syncHubNow() }
            }

        if store.hub.enabled {
            Toggle("Show Hub todos in list", isOn: $store.hub.showInList)
                .onChange(of: store.hub.showInList) { _, _ in store.savePrefsAndHub() }

            Text("Checking off Hub todos in Noto is local only. Mark them done on Teevo Hub when finished.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Hub user", selection: $store.hub.hubUser) {
                ForEach(hubUsers, id: \.self) { user in
                    Text(user.capitalized).tag(user)
                }
            }
            .onChange(of: store.hub.hubUser) { _, _ in store.savePrefsAndHub() }

            Stepper("Sync every \(store.hub.syncIntervalMinutes) min", value: $store.hub.syncIntervalMinutes, in: 1...60)
                .onChange(of: store.hub.syncIntervalMinutes) { _, _ in store.savePrefsAndHub() }

            Button("Sync Hub now") { store.syncHubNow() }
                .disabled(store.isSyncingHub)

            if let last = store.hub.lastSyncedAt {
                LabeledContent("Last sync") {
                    Text(relativeTime(last))
                        .foregroundStyle(.secondary)
                }
            }
            if let err = store.hubSyncError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        LabeledContent("Widget snapshot") {
            Text(FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.noto/todo-snapshot.json") ? "Ready" : "Pending")
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(_ ts: TimeInterval) -> String {
        let s = Int(Date().timeIntervalSince1970 - ts)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}

// MARK: - Profile Settings Panel

enum NotifPreset: String, CaseIterable {
    case focus, standard, loud

    var label: String {
        switch self {
        case .focus: return "Focus"
        case .standard: return "Standard"
        case .loud: return "Loud"
        }
    }

    var help: String {
        switch self {
        case .focus: return "Done only · 1 sentence · quieter"
        case .standard: return "Balanced defaults for this app"
        case .loud: return "All alerts · 2 sentences · full volume"
        }
    }
}

struct ProfileSettingsForm: View {
    @Binding var settings: ProfileSettings
    let profile: NotifProfile
    @State private var showAdvanced = false

    private var thresholds: Binding<[Int]> {
        Binding(
            get: { settings.resolvedThresholds },
            set: { settings.longRunningThresholds = $0 }
        )
    }

    var body: some View {
        Group {
            Section {
                Toggle("Profile enabled", isOn: $settings.enabled)
            }

            Section("Preset") {
                HStack(spacing: 8) {
                    ForEach(NotifPreset.allCases, id: \.self) { preset in
                        Button {
                            settings.applyPreset(preset, for: profile)
                        } label: {
                            Text(preset.label)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(preset.help)
                    }
                }
            }
            .disabled(!settings.enabled)

            Section("Essentials") {
                TextField("Title", text: $settings.titlePrefix, prompt: Text(profile.defaultTitle))
                Picker("Preview", selection: $settings.previewLength) {
                    Text("1 sentence").tag("sentence")
                    Text("2 sentences").tag("two")
                    Text("Full").tag("full")
                }
            }
            .disabled(!settings.enabled)

            SoundSettingsSection(
                title: "Finished",
                footer: "When the agent completes a response.",
                enabled: $settings.enableDone,
                sound: $settings.soundDone,
                volume: $settings.volumeDone,
                profileEnabled: settings.enabled
            )

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    SoundSettingsSection(
                        title: "Error",
                        footer: "When the agent hits an error.",
                        enabled: $settings.enableError,
                        sound: $settings.soundError,
                        volume: $settings.volumeError,
                        profileEnabled: settings.enabled,
                        embedded: true
                    )
                    SoundSettingsSection(
                        title: "Interrupted",
                        footer: "When a session is interrupted.",
                        enabled: $settings.enableInterrupt,
                        sound: $settings.soundInterrupt,
                        volume: $settings.volumeInterrupt,
                        profileEnabled: settings.enabled,
                        embedded: true
                    )
                    SoundSettingsSection(
                        title: "Approval",
                        footer: "When the agent needs your approval.",
                        enabled: $settings.enableApproval,
                        sound: $settings.soundApproval,
                        volume: $settings.volumeApproval,
                        profileEnabled: settings.enabled,
                        embedded: true
                    )

                    Divider()

                    Toggle("Long-running alerts", isOn: $settings.enableLongRunning)
                        .disabled(!settings.enabled)
                    if settings.enableLongRunning {
                        Picker("Sound", selection: $settings.soundLongRunning) {
                            ForEach(kSounds, id: \.self) { s in Text(s).tag(s) }
                            Divider()
                            if !kSounds.contains(settings.soundLongRunning) {
                                Text(URL(fileURLWithPath: settings.soundLongRunning).lastPathComponent)
                                    .tag(settings.soundLongRunning)
                            }
                            Text("Custom file…").tag("__custom__")
                        }
                        .disabled(!settings.enabled)
                        .onChange(of: settings.soundLongRunning) { _, val in
                            if val == "__custom__" { pickLongRunningSound() }
                        }
                        LabeledContent("Volume") {
                            HStack(spacing: 8) {
                                Slider(value: $settings.volumeLongRunning, in: 0...1)
                                Button { playSound(settings.soundLongRunning, volume: settings.volumeLongRunning) } label: {
                                    NotoSymbol(name: "play.circle", size: NotoDesign.Icon.Size.emphasis)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .disabled(!settings.enabled)

                        ForEach(thresholds.wrappedValue.indices, id: \.self) { idx in
                            LabeledContent(idx == 0 ? "Alert after" : "Also after") {
                                HStack {
                                    LongRunPicker(value: Binding(
                                        get: { thresholds.wrappedValue[idx] },
                                        set: { newVal in
                                            var next = thresholds.wrappedValue
                                            next[idx] = newVal
                                            thresholds.wrappedValue = next
                                        }
                                    ), disabled: !settings.enabled || !settings.enableLongRunning)
                                    if thresholds.wrappedValue.count > 1 {
                                        Button {
                                            var next = thresholds.wrappedValue
                                            next.remove(at: idx)
                                            thresholds.wrappedValue = next
                                        } label: {
                                            NotoSymbol(name: "minus.circle", size: NotoDesign.Icon.Size.emphasis)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }

                        if thresholds.wrappedValue.count < 5 {
                            Button {
                                var next = thresholds.wrappedValue
                                next.append((next.max() ?? 10) + 5)
                                thresholds.wrappedValue = next
                            } label: {
                                Label("Add alert threshold", systemImage: "plus.circle")
                            }
                            .disabled(!settings.enabled || !settings.enableLongRunning)
                        }
                    }

                    Divider()

                    Toggle("Quiet hours", isOn: $settings.quietEnabled)
                        .disabled(!settings.enabled)
                    if settings.quietEnabled {
                        LabeledContent("From") {
                            TimePicker(time: $settings.quietFrom, disabled: !settings.enabled)
                        }
                        LabeledContent("To") {
                            TimePicker(time: $settings.quietTo, disabled: !settings.enabled)
                        }
                    }
                }
            }
            .disabled(!settings.enabled)
        }
    }

    private func pickLongRunningSound() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound file (.aiff, .wav, .mp3, .m4a)"
        if panel.runModal() == .OK, let url = panel.url {
            settings.soundLongRunning = url.path
        } else {
            settings.soundLongRunning = "Glass"
        }
    }
}

private struct SoundSettingsSection: View {
    let title: String
    let footer: String
    @Binding var enabled: Bool
    @Binding var sound: String
    @Binding var volume: Double
    let profileEnabled: Bool
    var embedded: Bool = false

    var body: some View {
        Group {
            if embedded {
                embeddedContent
            } else {
                Section {
                    embeddedContent
                } header: {
                    Text(title)
                } footer: {
                    Text(footer)
                }
            }
        }
        .disabled(!profileEnabled)
    }

    @ViewBuilder
    private var embeddedContent: some View {
        if embedded {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Toggle(embedded ? "Enabled" : "Play sound", isOn: $enabled)
        Picker("Sound", selection: $sound) {
            ForEach(kSounds, id: \.self) { s in Text(s).tag(s) }
            Divider()
            if !kSounds.contains(sound) {
                Text(URL(fileURLWithPath: sound).lastPathComponent).tag(sound)
            }
            Text("Custom file…").tag("__custom__")
        }
        .disabled(!enabled)
        .onChange(of: sound) { _, val in
            if val == "__custom__" { pickCustomSound() }
        }
        LabeledContent("Volume") {
            HStack(spacing: 8) {
                Slider(value: $volume, in: 0...1)
                    .disabled(!enabled)
                Button { playSound(sound, volume: volume) } label: {
                    NotoSymbol(name: "play.circle", size: NotoDesign.Icon.Size.emphasis)
                }
                .buttonStyle(.borderless)
                .disabled(!enabled)
            }
        }
        if embedded {
            Divider()
        }
    }

    private func pickCustomSound() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
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

// MARK: - Quiet Hours / Time Picker

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
