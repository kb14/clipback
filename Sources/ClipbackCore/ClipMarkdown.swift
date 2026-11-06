import Foundation

/// The on-disk format of a clip: a markdown file with YAML front matter. This file is the source of truth;
/// any search index is rebuilt from it.
public enum ClipMarkdown {
    /// Path of the clip inside its library folder, e.g. `2026/10/2026-10-26-1432-lead-with-the-discovery.md`.
    public static func relativePath(for clip: Clip, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: clip.created)
        let year = String(format: "%04d", c.year ?? 0)
        let month = String(format: "%02d", c.month ?? 0)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let slug = slug(for: clip.title)
        let name = slug.isEmpty ? stamp : "\(stamp)-\(slug)"
        return "\(year)/\(month)/\(name).md"
    }

    public static func render(_ clip: Clip, timeZone: TimeZone = .current) -> String {
        var lines = ["---"]
        lines.append("id: \(clip.id)")
        lines.append("created: \(timestamp(clip.created, timeZone: timeZone))")
        lines.append("library: \(clip.library.rawValue)")
        lines.append("intent: \(clip.intent.rawValue)")
        lines.append("person: \(yaml(clip.person))")
        lines.append("tags: [\(clip.tags.map { yaml($0) }.joined(separator: ", "))]")
        lines.append("title: \(yaml(clip.title))")
        lines.append("source:")
        lines.append("  app: \(yaml(clip.source.app))")
        lines.append("  bundle_id: \(yaml(clip.source.bundleID))")
        lines.append("  window: \(yaml(clip.source.window))")
        lines.append("  url: \(yaml(clip.source.url))")
        lines.append("  file: \(yaml(clip.source.file))")
        lines.append("  page: \(clip.source.page.map(String.init) ?? "null")")
        lines.append("kind: \(clip.kind.rawValue)")
        lines.append("image: \(yaml(clip.image))")
        if let review = clip.review {
            lines.append("review:")
            lines.append("  next: \(day(review.next, timeZone: timeZone))")
            lines.append("  step: \(review.step)")
            lines.append("  status: \(review.isRetired ? "retired" : "active")")
            if let last = review.last {
                lines.append("  last: \(day(last, timeZone: timeZone))")
            }
        }
        if let done = clip.done {
            lines.append("done: \(day(done, timeZone: timeZone))")
        }
        if let archived = clip.archived {
            lines.append("archived: \(day(archived, timeZone: timeZone))")
        }
        lines.append("---")
        lines.append("")
        if clip.kind == .text {
            lines.append(blockquote(clip.selection))
        } else if let image = clip.image {
            lines.append("![](\(image.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image))")
        }

        let note = clip.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            lines.append("")
            lines.append("**Note:** \(note)")
        }

        if let ocr = clip.ocr?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
            lines.append("")
            lines.append("<details><summary>Text in image</summary>")
            lines.append("")
            lines.append(ocr)
            lines.append("")
            lines.append("</details>")
        }

        let before = clip.before ?? ""
        let after = clip.after ?? ""
        if !before.isEmpty || !after.isEmpty {
            lines.append("")
            lines.append("<details><summary>Context</summary>")
            lines.append("")
            lines.append(before + "==" + clip.selection.trimmingCharacters(in: .whitespacesAndNewlines) + "==" + after)
            lines.append("")
            lines.append("</details>")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// A short readable title: the first sentence of the selection, cut at a word boundary.
    public static func autoTitle(from selection: String, maxLength: Int = 70) -> String {
        let flat = selection.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var sentence = flat
        if let end = flat.firstMatch(of: /[.!?](\s|$)/) {
            sentence = String(flat[..<end.range.lowerBound])
        }
        guard sentence.count > maxLength else { return sentence }
        let cut = sentence.prefix(maxLength)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    /// Title for a screenshot: the first line of its text that reads like words (not a timestamp or a lone
    /// label), else the window title, else the app name.
    public static func imageTitle(ocr: String?, window: String?, app: String) -> String {
        let wordy = ocr?.split(separator: "\n").first { line in
            let words = line.split(whereSeparator: \.isWhitespace).filter { $0.filter(\.isLetter).count >= 2 }
            return words.count >= 2
        }
        if let wordy { return autoTitle(from: String(wordy)) }
        if let window, !window.isEmpty, window != app { return autoTitle(from: window) }
        return "Screenshot from \(app)"
    }

    /// Lowercase ASCII words joined by dashes, at most six words.
    public static func slug(for title: String) -> String {
        let folded = title.applyingTransform(.stripDiacritics, reverse: false) ?? title
        let words = folded.lowercased()
            .split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
            .prefix(6)
        return words.joined(separator: "-")
    }

    /// Keeps whole words at the cut edges of the text around a selection.
    public static func trimContext(before: String, after: String, wasCutBefore: Bool, wasCutAfter: Bool) -> (String, String) {
        var head = Substring(before)
        if wasCutBefore, let space = head.firstIndex(where: \.isWhitespace) {
            head = head[head.index(after: space)...]
        }
        var tail = Substring(after)
        if wasCutAfter, let space = tail.lastIndex(where: \.isWhitespace) {
            tail = tail[..<space]
        }
        return (String(head), String(tail))
    }

    static func yaml(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func blockquote(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone))
    }

    private static func day(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }
}
