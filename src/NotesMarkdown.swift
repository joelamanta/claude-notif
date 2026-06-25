import Foundation

enum NotchNotesFormatAction: Equatable {
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case link
    case inlineCode
    case codeBlock
    case blockquote
    case bulletList
    case numberedList
    case taskList
}

enum NotchNotesMarkdown {
    static func displayTitle(for body: String, fallback: String = "Untitled") -> String {
        let line = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !line.isEmpty else { return fallback }
        var cleaned = line
        while cleaned.first == "#" || cleaned.first == " " {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return fallback }
        return String(cleaned.prefix(80))
    }

    static func syncTitle(from body: String, into title: inout String) {
        title = displayTitle(for: body)
    }

    static func apply(_ action: NotchNotesFormatAction, to text: String, selectedRange: NSRange) -> (String, NSRange) {
        if text.isEmpty {
            return applyToEmpty(action)
        }
        let ns = text as NSString
        let safeLoc = min(max(0, selectedRange.location), ns.length)
        let safeLen = min(max(0, selectedRange.length), ns.length - safeLoc)
        let range = NSRange(location: safeLoc, length: safeLen)
        let selected = safeLen > 0 ? ns.substring(with: range) : ""

        switch action {
        case .heading(let level):
            return prefixLines(text: text, range: range, prefix: String(repeating: "#", count: max(1, min(3, level))) + " ")
        case .bold:
            return wrap(text: text, range: range, selected: selected, marker: "**", placeholder: "bold")
        case .italic:
            return wrap(text: text, range: range, selected: selected, marker: "*", placeholder: "italic")
        case .strikethrough:
            return wrap(text: text, range: range, selected: selected, marker: "~~", placeholder: "text")
        case .link:
            if selected.isEmpty {
                return insert(text: text, at: range, snippet: "[label](https://)")
            }
            return insert(text: text, at: range, snippet: "[\(selected)](https://)")
        case .inlineCode:
            return wrap(text: text, range: range, selected: selected, marker: "`", placeholder: "code")
        case .codeBlock:
            let block = selected.isEmpty ? "```\n\n```" : "```\n\(selected)\n```"
            return insert(text: text, at: range, snippet: block)
        case .blockquote:
            return prefixLines(text: text, range: range, prefix: "> ")
        case .bulletList:
            return prefixLines(text: text, range: range, prefix: "- ")
        case .numberedList:
            return prefixLines(text: text, range: range, prefix: "1. ", numbered: true)
        case .taskList:
            return prefixLines(text: text, range: range, prefix: "- [ ] ")
        }
    }

    private static func applyToEmpty(_ action: NotchNotesFormatAction) -> (String, NSRange) {
        let snippet: String
        switch action {
        case .heading(let level):
            let hashes = String(repeating: "#", count: max(1, min(3, level)))
            snippet = "\(hashes) "
        case .bold: snippet = "**bold**"
        case .italic: snippet = "*italic*"
        case .strikethrough: snippet = "~~text~~"
        case .link: snippet = "[label](https://)"
        case .inlineCode: snippet = "`code`"
        case .codeBlock: snippet = "```\n\n```"
        case .blockquote: snippet = "> "
        case .bulletList: snippet = "- "
        case .numberedList: snippet = "1. "
        case .taskList: snippet = "- [ ] "
        }
        return (snippet, NSRange(location: (snippet as NSString).length, length: 0))
    }

    private static func wrap(
        text: String,
        range: NSRange,
        selected: String,
        marker: String,
        placeholder: String
    ) -> (String, NSRange) {
        let inner = selected.isEmpty ? placeholder : selected
        let snippet = "\(marker)\(inner)\(marker)"
        let result = insert(text: text, at: range, snippet: snippet)
        if selected.isEmpty {
            let start = result.1.location + marker.count
            return (result.0, NSRange(location: start, length: placeholder.count))
        }
        return result
    }

    private static func insert(text: String, at range: NSRange, snippet: String) -> (String, NSRange) {
        let ns = text as NSString
        let updated = ns.replacingCharacters(in: range, with: snippet)
        let newRange = NSRange(location: range.location + (snippet as NSString).length, length: 0)
        return (updated, newRange)
    }

    private static func prefixLines(
        text: String,
        range: NSRange,
        prefix: String,
        numbered: Bool = false
    ) -> (String, NSRange) {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: range)
        let chunk = ns.substring(with: lineRange)
        let lines = chunk.components(separatedBy: "\n")
        var index = 1
        let transformed = lines.enumerated().map { idx, line -> String in
            let isLastEmpty = idx == lines.count - 1 && line.isEmpty
            if isLastEmpty && lines.count > 1 { return line }
            if line.hasPrefix(prefix) || line.hasPrefix("> ") || line.hasPrefix("#") { return line }
            if numbered {
                let numberedPrefix = "\(index). "
                index += 1
                return numberedPrefix + line
            }
            return prefix + line
        }.joined(separator: "\n")
        let updated = ns.replacingCharacters(in: lineRange, with: transformed)
        let newLoc = lineRange.location + (transformed as NSString).length
        return (updated, NSRange(location: newLoc, length: 0))
    }
}
