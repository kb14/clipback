import Foundation

/// Reads a clip back from the markdown that `ClipMarkdown.render` writes. Tolerant of hand edits: unknown keys
/// are ignored and missing ones fall back to defaults.
public enum ClipParser {
    public static func parse(_ text: String, calendar: Calendar = .current) -> Clip? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        let fields = frontMatter(Array(lines[1..<end]))
        let body = Array(lines[(end + 1)...])

        guard let id = fields["id"]?.string,
              let created = fields["created"]?.string.flatMap(parseTimestamp) else { return nil }
        let kind = fields["kind"]?.string.flatMap(ClipKind.init(rawValue:)) ?? .text
        let sections = bodySections(body)

        var review: ReviewState?
        if let next = fields["review.next"]?.string.flatMap({ parseDay($0, calendar: calendar) }) {
            review = ReviewState(
                next: next,
                step: fields["review.step"]?.string.flatMap { Int($0) } ?? 0,
                isRetired: fields["review.status"]?.string == "retired",
                last: fields["review.last"]?.string.flatMap { parseDay($0, calendar: calendar) }
            )
        }

        return Clip(
            id: id,
            created: created,
            library: fields["library"]?.string.flatMap(Library.init(rawValue:)) ?? .personal,
            intent: fields["intent"]?.string.flatMap(Intent.init(rawValue:)) ?? .save,
            person: fields["person"]?.string,
            tags: fields["tags"]?.list ?? [],
            title: fields["title"]?.string ?? "",
            source: ClipSource(
                app: fields["source.app"]?.string ?? "Unknown app",
                bundleID: fields["source.bundle_id"]?.string,
                window: fields["source.window"]?.string,
                url: fields["source.url"]?.string,
                file: fields["source.file"]?.string,
                page: fields["source.page"]?.string.flatMap { Int($0) }
            ),
            kind: kind,
            image: fields["image"]?.string,
            ocr: sections.ocr,
            selection: sections.selection,
            note: sections.note,
            before: sections.before,
            after: sections.after,
            review: review,
            done: fields["done"]?.string.flatMap { parseDay($0, calendar: calendar) },
            archived: fields["archived"]?.string.flatMap { parseDay($0, calendar: calendar) }
        )
    }

    // MARK: Front matter

    enum Value: Equatable {
        case scalar(String?)
        case list([String])

        var string: String? {
            if case .scalar(let value) = self { return value }
            return nil
        }

        var list: [String]? {
            if case .list(let values) = self { return values }
            return nil
        }
    }

    /// Flattens one level of nesting into dotted keys, e.g. `source.app`.
    static func frontMatter(_ lines: [String]) -> [String: Value] {
        var fields: [String: Value] = [:]
        var parent: String?
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let isNested = line.hasPrefix("  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
            let raw = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !isNested {
                parent = raw.isEmpty ? key : nil
                if raw.isEmpty { continue }
                fields[key] = value(raw)
            } else if let parent {
                fields["\(parent).\(key)"] = value(raw)
            }
        }
        return fields
    }

    static func value(_ raw: String) -> Value {
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            return .list(listItems(String(raw.dropFirst().dropLast())))
        }
        return .scalar(scalar(raw))
    }

    private static func scalar(_ raw: String) -> String? {
        if raw == "null" || raw == "~" || raw.isEmpty { return nil }
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return raw }
        return unescape(String(raw.dropFirst().dropLast()))
    }

    /// Splits `"a", "b, c", d` on commas outside quotes.
    private static func listItems(_ inner: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for char in inner {
            if escaped { current.append(char); escaped = false; continue }
            if char == "\\" && inQuotes { current.append(char); escaped = true; continue }
            if char == "\"" { inQuotes.toggle(); current.append(char); continue }
            if char == "," && !inQuotes {
                items.append(current)
                current = ""
                continue
            }
            current.append(char)
        }
        items.append(current)
        return items.compactMap { scalar($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for char in text {
            if escaped {
                switch char {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                result.append(char)
            }
        }
        return result
    }

    // MARK: Body

    struct Sections {
        var selection = ""
        var note = ""
        var before: String?
        var after: String?
        var ocr: String?
    }

    static func bodySections(_ lines: [String]) -> Sections {
        var sections = Sections()
        var quote: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix(">") {
                quote.append(line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line.dropFirst()))
            } else if line.hasPrefix("**Note:**") {
                sections.note = line.dropFirst("**Note:**".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("<details><summary>") {
                let summary = line.replacingOccurrences(of: "<details><summary>", with: "").replacingOccurrences(of: "</summary>", with: "")
                var content: [String] = []
                index += 1
                while index < lines.count, lines[index] != "</details>" {
                    content.append(lines[index])
                    index += 1
                }
                let text = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if summary == "Context" {
                    (sections.before, sections.after) = splitContext(text)
                } else if summary == "Text in image" {
                    sections.ocr = text
                }
            }
            index += 1
        }
        sections.selection = quote.joined(separator: "\n")
        return sections
    }

    /// Context is written as `before==selection==after`.
    private static func splitContext(_ text: String) -> (String?, String?) {
        guard let open = text.range(of: "=="),
              let close = text.range(of: "==", options: .backwards), close.lowerBound > open.upperBound else { return (nil, nil) }
        let before = String(text[..<open.lowerBound])
        let after = String(text[close.upperBound...])
        return (before.isEmpty ? nil : before, after.isEmpty ? nil : after)
    }

    // MARK: Dates

    private static func parseTimestamp(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle(timeZoneSeparator: .colon).parse(text)
    }

    private static func parseDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
