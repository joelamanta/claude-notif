import Foundation
import Combine

// MARK: - Todo models

enum NotchTodoSection: String, Codable, CaseIterable {
    case now, today

    var title: String {
        switch self {
        case .now: return "Now"
        case .today: return "Today"
        }
    }
}

enum NotchTodoOrigin: String, Codable {
    case local, rolled, template, teevoHub
}

enum NotchTodoRepeat: String, Codable, CaseIterable {
    case none, daily, weekdays, weekly

    var label: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        }
    }

    func nextOccurrence(after date: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none: return nil
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))
        case .weekdays:
            var next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
            for _ in 0..<7 {
                let wd = cal.component(.weekday, from: next)
                if wd != 1 && wd != 7 { return next }
                next = cal.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: date))
        }
    }
}

struct NotchTodoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isDone: Bool
    var createdAt: TimeInterval
    var section: NotchTodoSection
    var origin: NotchTodoOrigin
    var hubId: String?
    var repeatRule: NotchTodoRepeat
    var rolledFrom: String?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        section: NotchTodoSection = .today,
        origin: NotchTodoOrigin = .local,
        hubId: String? = nil,
        repeatRule: NotchTodoRepeat = .none,
        rolledFrom: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.section = isDone ? .today : section
        self.origin = origin
        self.hubId = hubId
        self.repeatRule = repeatRule
        self.rolledFrom = rolledFrom
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isDone, createdAt, section, origin, hubId, repeatRule, rolledFrom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(TimeInterval.self, forKey: .createdAt) ?? Date().timeIntervalSince1970
        section = try c.decodeIfPresent(NotchTodoSection.self, forKey: .section) ?? .today
        origin = try c.decodeIfPresent(NotchTodoOrigin.self, forKey: .origin) ?? .local
        hubId = try c.decodeIfPresent(String.self, forKey: .hubId)
        repeatRule = try c.decodeIfPresent(NotchTodoRepeat.self, forKey: .repeatRule) ?? .none
        rolledFrom = try c.decodeIfPresent(String.self, forKey: .rolledFrom)
    }
}

struct NotchTodoTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var items: [String]

    init(id: UUID = UUID(), name: String, items: [String]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

struct NotchTodoPrefs: Codable, Equatable {
    var autoRollUnfinished: Bool = true
    var maxNowItems: Int = 3
}

struct NotchHubPrefs: Codable, Equatable {
    var enabled: Bool = false
    /// When false, Hub todos stay synced but are hidden from the Noto todo list and widget.
    var showInList: Bool = true
    /// Hub todo IDs checked off in Noto only — never written back to Teevo Hub.
    var locallyDoneHubIds: [String] = []
    var supabaseURL: String = "https://rlxpcdeishhahbtyitri.supabase.co"
    var supabaseAnonKey: String = NotchHubPrefs.defaultAnonKey
    var hubUser: String = "joel"
    var syncIntervalMinutes: Int = 5
    var lastSyncedAt: TimeInterval?

    static let defaultAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJseHBjZGVpc2hoYWhidHlpdHJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwOTI3MDEsImV4cCI6MjA5MjY2ODcwMX0.3dWv-iW7tnY5WF_9vOoS1WhQ0HSG5pNxgl2OeQilZp0"
}

struct NotchTodoFile: Codable {
    var days: [String: [NotchTodoItem]] = [:]
    var templates: [NotchTodoTemplate] = []
    var prefs: NotchTodoPrefs = NotchTodoPrefs()
    var hub: NotchHubPrefs = NotchHubPrefs()
    var pendingRepeats: [NotchTodoItem] = []
}

struct NotchTodoLayoutMetrics {
    let nowCount: Int
    let todayCount: Int
    let doneCount: Int
    let sectionCount: Int
    let rolledBanner: Bool
    let hiddenHubBanner: Bool
    let interSectionGaps: Int
    let visibleRowCount: Int

    static let empty = NotchTodoLayoutMetrics(
        nowCount: 0, todayCount: 0, doneCount: 0, sectionCount: 0,
        rolledBanner: false, hiddenHubBanner: false, interSectionGaps: 0, visibleRowCount: 0
    )
}

// MARK: - Store

final class NotchDailyTodoStore: ObservableObject {
    static let shared = NotchDailyTodoStore()

    @Published private(set) var items: [NotchTodoItem] = []
    @Published private(set) var templates: [NotchTodoTemplate] = []
    @Published var prefs = NotchTodoPrefs()
    @Published var hub = NotchHubPrefs()
    @Published private(set) var rolledBannerCount = 0
    @Published var doneSectionExpanded = false
    @Published private(set) var isSyncingHub = false
    @Published private(set) var hubSyncError: String?

    var onItemsChanged: (() -> Void)?

    private static var notoDir: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/.noto")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { notoDir.appendingPathComponent("daily-todos.json") }
    private static var legacyURL: URL { notoDir.appendingPathComponent("todo-store.json") }

    private var dayKey = NotchDailyTodoStore.todayKey()
    private var file = NotchTodoFile()
    private var hubSyncTimer: Timer?

    init() {
        load()
        ensureDefaultTemplates()
        startHubSyncTimer()
    }

    deinit {
        hubSyncTimer?.invalidate()
    }

    static func todayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func todayLabel(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale.current
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    private func isVisibleInList(_ item: NotchTodoItem) -> Bool {
        item.origin != .teevoHub || hub.showInList
    }

    var nowItems: [NotchTodoItem] {
        items.filter { !$0.isDone && $0.section == .now && isVisibleInList($0) }
    }
    var todayItems: [NotchTodoItem] {
        items.filter { !$0.isDone && $0.section == .today && isVisibleInList($0) }
    }
    var doneItems: [NotchTodoItem] { items.filter { $0.isDone && isVisibleInList($0) } }
    var visibleItems: [NotchTodoItem] { items.filter(isVisibleInList) }
    var hiddenHubOpenCount: Int {
        guard hub.enabled, !hub.showInList else { return 0 }
        return items.filter { $0.origin == .teevoHub && !$0.isDone }.count
    }

    func setHubTodosVisible(_ visible: Bool) {
        guard hub.showInList != visible else { return }
        hub.showInList = visible
        savePrefsAndHub()
        onItemsChanged?()
    }

    var layoutMetrics: NotchTodoLayoutMetrics {
        let now = nowItems.count
        let today = todayItems.count
        let done = doneItems.count
        var sections = 0
        if now > 0 { sections += 1 }
        if today > 0 || (now == 0 && today == 0 && done == 0) { sections += 1 }
        if done > 0 { sections += 1 }
        let doneVisible = doneSectionExpanded ? done : min(done, 2)
        let rows = now + today + doneVisible + (done > 2 && !doneSectionExpanded ? 1 : 0)
        var interSectionGaps = 0
        if now > 0 && today > 0 { interSectionGaps += 1 }
        if now > 0 && today == 0 && done > 0 { interSectionGaps += 1 }
        if today > 0 && done > 0 { interSectionGaps += 1 }
        return NotchTodoLayoutMetrics(
            nowCount: now,
            todayCount: today,
            doneCount: done,
            sectionCount: sections,
            rolledBanner: rolledBannerCount > 0,
            hiddenHubBanner: hiddenHubOpenCount > 0,
            interSectionGaps: interSectionGaps,
            visibleRowCount: max(rows, visibleItems.isEmpty ? 1 : rows)
        )
    }

    func refreshDayIfNeeded() {
        let key = Self.todayKey()
        guard key != dayKey else { return }

        let previousKey = dayKey
        let previousItems = items
        saveCurrentDay()

        dayKey = key
        items = file.days[dayKey] ?? []
        rolledBannerCount = 0

        applyPendingRepeats()
        if prefs.autoRollUnfinished, items.isEmpty {
            let unfinished = previousItems.filter { !$0.isDone }
            if !unfinished.isEmpty {
                for var item in unfinished {
                    item.id = UUID()
                    item.section = .today
                    item.origin = .rolled
                    item.rolledFrom = previousKey
                    item.hubId = nil
                    items.append(item)
                }
                rolledBannerCount = unfinished.count
            }
        }

        persist()
    }

    func dismissRolledBanner() {
        rolledBannerCount = 0
    }

    func add(_ title: String, section: NotchTodoSection = .today) {
        refreshDayIfNeeded()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(NotchTodoItem(title: trimmed, section: section))
        persist()
    }

    func toggle(_ id: UUID) {
        refreshDayIfNeeded()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let wasDone = items[idx].isDone
        items[idx].isDone.toggle()

        if items[idx].isDone {
            scheduleRepeatIfNeeded(from: items[idx])
            if let hubId = items[idx].hubId, !hub.locallyDoneHubIds.contains(hubId) {
                hub.locallyDoneHubIds.append(hubId)
            }
        } else if wasDone, let hubId = items[idx].hubId {
            hub.locallyDoneHubIds.removeAll { $0 == hubId }
        }

        persist()
    }

    func remove(_ id: UUID) {
        refreshDayIfNeeded()
        items.removeAll { $0.id == id }
        persist()
    }

    func moveSection(_ id: UUID, to section: NotchTodoSection) {
        refreshDayIfNeeded()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[idx].isDone else { return }

        if section == .now {
            let nowCount = nowItems.count
            if nowCount >= prefs.maxNowItems, items[idx].section != .now {
                if let oldest = nowItems.first?.id, oldest != id {
                    if let oidx = items.firstIndex(where: { $0.id == oldest }) {
                        items[oidx].section = .today
                    }
                }
            }
        }

        items[idx].section = section
        persist()
    }

    func cycleRepeat(_ id: UUID) {
        refreshDayIfNeeded()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let all = NotchTodoRepeat.allCases
        if let i = all.firstIndex(of: items[idx].repeatRule) {
            items[idx].repeatRule = all[(i + 1) % all.count]
        }
        persist()
    }

    func applyTemplate(_ templateID: UUID) {
        guard let template = templates.first(where: { $0.id == templateID }) else { return }
        refreshDayIfNeeded()
        for title in template.items {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            items.append(NotchTodoItem(title: trimmed, section: .today, origin: .template))
        }
        persist()
    }

    func savePrefsAndHub() {
        file.prefs = prefs
        file.hub = hub
        persistMetadataOnly()
        startHubSyncTimer()
    }

    func syncHubNow() {
        Task { await syncHub(force: true) }
    }

    private func scheduleRepeatIfNeeded(from item: NotchTodoItem) {
        guard item.repeatRule != .none, item.origin != .teevoHub else { return }
        guard let due = item.repeatRule.nextOccurrence(after: Date()) else { return }
        var next = item
        next.id = UUID()
        next.isDone = false
        next.createdAt = due.timeIntervalSince1970
        next.section = .today
        next.origin = .local
        next.rolledFrom = nil
        next.hubId = nil
        file.pendingRepeats.append(next)
    }

    private func applyPendingRepeats() {
        guard !file.pendingRepeats.isEmpty else { return }
        let todayStart = Calendar.current.startOfDay(for: Date())
        var keep: [NotchTodoItem] = []
        for var item in file.pendingRepeats {
            let due = Date(timeIntervalSince1970: item.createdAt)
            if Calendar.current.startOfDay(for: due) <= todayStart {
                item.id = UUID()
                item.isDone = false
                items.append(item)
            } else {
                keep.append(item)
            }
        }
        file.pendingRepeats = keep
    }

    private func ensureDefaultTemplates() {
        guard templates.isEmpty else { return }
        templates = [
            NotchTodoTemplate(name: "Morning standup", items: [
                "Review Task Center",
                "Check Hub todo alerts",
                "Clear Noto inbox",
            ]),
            NotchTodoTemplate(name: "Pre-ship", items: [
                "Test locally",
                "Deploy",
                "Notify team",
            ]),
            NotchTodoTemplate(name: "Weekly review", items: [
                "Review open todos",
                "Archive completed",
                "Plan next week",
            ]),
        ]
        file.templates = templates
        persistMetadataOnly()
    }

    private func load() {
        let today = Self.todayKey()
        let url = FileManager.default.fileExists(atPath: Self.fileURL.path) ? Self.fileURL : Self.legacyURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(NotchTodoFile.self, from: data) {
            file = decoded
        }
        dayKey = today
        items = file.days[dayKey] ?? []
        templates = file.templates
        prefs = file.prefs
        hub = file.hub
        if hub.supabaseAnonKey.isEmpty { hub.supabaseAnonKey = NotchHubPrefs.defaultAnonKey }
        rollFromYesterdayIfNeeded()
        applyPendingRepeats()
        pruneOldDays()
        NotoTodoSnapshotWriter.write(store: self)
    }

    private func rollFromYesterdayIfNeeded() {
        guard prefs.autoRollUnfinished, items.isEmpty else { return }
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yKey = Self.todayKey(for: yesterday)
        let previousItems = file.days[yKey] ?? []
        let unfinished = previousItems.filter { !$0.isDone }
        guard !unfinished.isEmpty else { return }
        for var item in unfinished {
            item.id = UUID()
            item.section = .today
            item.origin = .rolled
            item.rolledFrom = yKey
            item.hubId = nil
            items.append(item)
        }
        rolledBannerCount = unfinished.count
    }

    private func saveCurrentDay() {
        file.days[dayKey] = items
    }

    private func persistMetadataOnly() {
        file.templates = templates
        file.prefs = prefs
        file.hub = hub
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func persist() {
        saveCurrentDay()
        file.templates = templates
        file.prefs = prefs
        file.hub = hub
        pruneOldDays()
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
        NotoTodoSnapshotWriter.write(store: self)
        onItemsChanged?()
    }

    private func pruneOldDays() {
        let keep = Set(
            (0..<14).compactMap {
                Calendar.current.date(byAdding: .day, value: -$0, to: Date()).map(Self.todayKey(for:))
            }
        )
        file.days = file.days.filter { keep.contains($0.key) }
    }

    // MARK: Hub sync

    private func startHubSyncTimer() {
        hubSyncTimer?.invalidate()
        hubSyncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.syncHubIfDue()
        }
    }

    private func syncHubIfDue() {
        guard hub.enabled else { return }
        let interval = TimeInterval(max(hub.syncIntervalMinutes, 1) * 60)
        if let last = hub.lastSyncedAt, Date().timeIntervalSince1970 - last < interval { return }
        Task { await syncHub(force: false) }
    }

    @MainActor
    func syncHub(force: Bool) async {
        guard hub.enabled else { return }
        if isSyncingHub, !force { return }
        isSyncingHub = true
        hubSyncError = nil
        defer { isSyncingHub = false }

        do {
            let remote = try await TeevoHubTodoClient.fetchAssignedTodos(hub: hub)
            mergeHubTodos(remote)
            hub.lastSyncedAt = Date().timeIntervalSince1970
            file.hub = hub
            persist()
        } catch {
            hubSyncError = error.localizedDescription
        }
    }

    private func mergeHubTodos(_ remote: [TeevoHubTodoRow]) {
        refreshDayIfNeeded()
        let remoteIDs = Set(remote.map(\.id))

        items.removeAll { item in
            guard item.origin == .teevoHub, let hid = item.hubId else { return false }
            return !remoteIDs.contains(hid)
        }

        for row in remote where row.status != "done" {
            if hub.locallyDoneHubIds.contains(row.id) {
                if let idx = items.firstIndex(where: { $0.hubId == row.id }) {
                    items[idx].title = row.title
                    items[idx].isDone = true
                }
                continue
            }
            if let idx = items.firstIndex(where: { $0.hubId == row.id }) {
                items[idx].title = row.title
            } else {
                items.append(NotchTodoItem(
                    title: row.title,
                    section: .today,
                    origin: .teevoHub,
                    hubId: row.id
                ))
            }
        }

        for row in remote where row.status == "done" {
            hub.locallyDoneHubIds.removeAll { $0 == row.id }
            items.removeAll { $0.hubId == row.id }
        }
    }
}

// MARK: - Teevo Hub client

struct TeevoHubTodoRow: Decodable {
    let id: String
    let title: String
    let status: String
    let assignee: String?
    let assignees: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, status, assignee, assignees
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int64.self, forKey: .id) {
            id = String(n)
        } else {
            let n = try c.decode(Double.self, forKey: .id)
            id = String(Int64(n))
        }
        title = try c.decode(String.self, forKey: .title)
        status = try c.decode(String.self, forKey: .status)
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee)
        assignees = try c.decodeIfPresent([String].self, forKey: .assignees)
    }
}

enum TeevoHubTodoClient {
    static func fetchAssignedTodos(hub: NotchHubPrefs) async throws -> [TeevoHubTodoRow] {
        guard let url = URL(string: "\(hub.supabaseURL)/rest/v1/todos?select=id,title,status,assignee,assignees&deleted_at=is.null&order=sort_order.asc.nullslast") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(hub.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(hub.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder().decode([TeevoHubTodoRow].self, from: data)
        let user = hub.hubUser.lowercased()
        return rows.filter { row in
            let assignees = row.assignees ?? []
            if assignees.map({ $0.lowercased() }).contains(user) { return true }
            return row.assignee?.lowercased() == user
        }
    }

}

// MARK: - Widget snapshot

enum NotoTodoSnapshotWriter {
    struct SnapshotItem: Codable {
        let id: String
        let title: String
        let isDone: Bool
        let section: String
        let origin: String
    }

    struct Snapshot: Codable {
        let updatedAt: TimeInterval
        let todayLabel: String
        let now: [SnapshotItem]
        let today: [SnapshotItem]
        let done: [SnapshotItem]
        let openCount: Int
        let doneCount: Int
        let hubSyncedAt: TimeInterval?
    }

    static func write(store: NotchDailyTodoStore) {
        let snap = Snapshot(
            updatedAt: Date().timeIntervalSince1970,
            todayLabel: NotchDailyTodoStore.todayLabel(),
            now: store.nowItems.map(mapItem),
            today: store.todayItems.map(mapItem),
            done: store.doneItems.map(mapItem),
            openCount: store.nowItems.count + store.todayItems.count,
            doneCount: store.doneItems.count,
            hubSyncedAt: store.hub.lastSyncedAt
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let paths = [
            URL(fileURLWithPath: NSHomeDirectory() + "/.noto/todo-snapshot.json"),
        ]
        for url in paths {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func mapItem(_ item: NotchTodoItem) -> SnapshotItem {
        SnapshotItem(
            id: item.id.uuidString,
            title: item.title,
            isDone: item.isDone,
            section: item.section.rawValue,
            origin: item.origin.rawValue
        )
    }
}
