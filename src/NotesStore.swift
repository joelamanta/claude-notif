import Foundation
import Combine

// MARK: - Text bridge (format actions without SwiftUI update-cycle crashes)

final class NotchNotesTextBridge {
    weak var coordinator: AnyObject?
    private var formatTarget: NotchNotesFormatTarget? {
        coordinator as? NotchNotesFormatTarget
    }

    func apply(_ action: NotchNotesFormatAction) {
        formatTarget?.applyFormat(action)
    }

    func focusEditor() {
        formatTarget?.focusEditor()
    }
}

protocol NotchNotesFormatTarget: AnyObject {
    func applyFormat(_ action: NotchNotesFormatAction)
    func focusEditor()
}

// MARK: - Notes models

struct NotchNotePage: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: TimeInterval
    var updatedAt: TimeInterval
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        body: String = "",
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }
}

struct NotchNotesFile: Codable, Equatable {
    var pages: [NotchNotePage] = []
    var activePageId: UUID?
}

struct NotchNotesLayoutMetrics: Equatable {
    var browseExpanded: Bool
    var browseRowCount: Int
    var pageCount: Int

    static let empty = NotchNotesLayoutMetrics(browseExpanded: false, browseRowCount: 0, pageCount: 0)
}

// MARK: - Store

final class NotchNotesStore: ObservableObject {
    static let shared = NotchNotesStore()

    @Published private(set) var pages: [NotchNotePage] = []
    @Published var activePageId: UUID?
    @Published var browseExpanded = false
    @Published var browseQuery = ""

    var onPagesChanged: (() -> Void)?

    private static var notoDir: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/.noto")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { notoDir.appendingPathComponent("notes.json") }

    init() {
        load()
        ensureActivePage()
    }

    var sortedPages: [NotchNotePage] {
        pages.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var activePage: NotchNotePage? {
        guard let activePageId else { return pages.first }
        return pages.first { $0.id == activePageId } ?? pages.first
    }

    var activeIndex: Int {
        guard let active = activePage else { return 0 }
        let ordered = sortedPages
        return ordered.firstIndex(where: { $0.id == active.id }) ?? 0
    }

    var browsablePages: [NotchNotePage] {
        let query = browseQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedPages }
        return sortedPages.filter { page in
            let title = NotchNotesMarkdown.displayTitle(for: page.body, fallback: page.title).lowercased()
            return title.contains(query) || page.body.lowercased().contains(query)
        }
    }

    var layoutMetrics: NotchNotesLayoutMetrics {
        let browseRows: Int
        if browseExpanded {
            browseRows = browsablePages.isEmpty ? 1 : min(browsablePages.count, 8)
        } else {
            browseRows = 0
        }
        return NotchNotesLayoutMetrics(
            browseExpanded: browseExpanded,
            browseRowCount: browseRows,
            pageCount: pages.count
        )
    }

    func selectPage(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        activePageId = id
        persistMetadataOnly()
    }

    func stepPage(delta: Int) {
        let ordered = sortedPages
        guard !ordered.isEmpty else { return }
        let idx = activeIndex
        let next = (idx + delta + ordered.count) % ordered.count
        selectPage(ordered[next].id)
    }

    @discardableResult
    func createPage(title: String = "Untitled") -> UUID {
        let page = NotchNotePage(title: title)
        pages.append(page)
        activePageId = page.id
        persist()
        return page.id
    }

    func updateActiveTitle(_ title: String) {
        guard let id = activePageId ?? pages.first?.id,
              let idx = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[idx].title = title
        pages[idx].updatedAt = Date().timeIntervalSince1970
        persist()
    }

    func updateActiveBody(_ body: String) {
        guard let id = activePageId ?? pages.first?.id,
              let idx = pages.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = Self.sanitizeBody(body)
        pages[idx].body = cleaned
        NotchNotesMarkdown.syncTitle(from: cleaned, into: &pages[idx].title)
        pages[idx].updatedAt = Date().timeIntervalSince1970
        persist(notifyLayout: false)
    }

    /// Strip accidental placeholder text; never persist UI placeholder copy.
    static func sanitizeBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let placeholders = ["Start writing…", "Start writing...", "aStart writing…"]
        if placeholders.contains(where: { body.hasPrefix($0) || body == $0 }) {
            return ""
        }
        return body
    }

    func togglePagePin(_ id: UUID) {
        guard let idx = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[idx].isPinned.toggle()
        pages[idx].updatedAt = Date().timeIntervalSince1970
        persist()
    }

    func deletePage(_ id: UUID) {
        pages.removeAll { $0.id == id }
        if activePageId == id {
            activePageId = sortedPages.first?.id
        }
        if pages.isEmpty {
            _ = createPage()
        } else {
            persist()
        }
    }

    func deleteActivePage() {
        guard let id = activePageId ?? pages.first?.id else { return }
        deletePage(id)
    }

    var canDeleteActivePage: Bool {
        pages.count > 1 || !(activePage?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func toggleBrowse() {
        browseExpanded.toggle()
        if !browseExpanded { browseQuery = "" }
        onPagesChanged?()
    }

    func closeBrowse() {
        browseExpanded = false
        browseQuery = ""
        onPagesChanged?()
    }

    static func relativeDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Persistence

    private func ensureActivePage() {
        if pages.isEmpty {
            _ = createPage()
            return
        }
        if activePageId == nil || !pages.contains(where: { $0.id == activePageId }) {
            activePageId = sortedPages.first?.id
            persistMetadataOnly()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path),
              let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(NotchNotesFile.self, from: data) else {
            pages = []
            activePageId = nil
            return
        }
        pages = decoded.pages.map { page in
            var p = page
            p.body = Self.sanitizeBody(p.body)
            if p.title == "Untitled", !p.body.isEmpty {
                NotchNotesMarkdown.syncTitle(from: p.body, into: &p.title)
            }
            return p
        }
        activePageId = decoded.activePageId
    }

    private func persist(notifyLayout: Bool = true) {
        persistMetadataOnly(notifyLayout: notifyLayout)
    }

    private func persistMetadataOnly(notifyLayout: Bool = true) {
        let payload = NotchNotesFile(pages: pages, activePageId: activePageId)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        if notifyLayout {
            onPagesChanged?()
        }
    }
}
