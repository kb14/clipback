import Foundation

/// Line-level structure of clipped text, so notes copied from Granola, Claude or docs keep their headings and
/// bullets instead of showing raw `#` and `-`. Inline styling (bold, links) is left to the view.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, marker: String, text: String)
    case paragraph(String)
    /// A blank line between blocks. Runs of blank lines collapse into one.
    case gap
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = (line.count - line.drop(while: { $0 == " " }).count) / 2

            if trimmed.isEmpty {
                if let last = blocks.last, last != .gap { blocks.append(.gap) }
            } else if let match = trimmed.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                blocks.append(.heading(level: match.output.1.count, text: String(match.output.2)))
            } else if let match = trimmed.firstMatch(of: /^[-*•]\s+(.+)$/) {
                blocks.append(.bullet(indent: indent, text: String(match.output.1)))
            } else if let match = trimmed.firstMatch(of: /^(\d{1,3}[.)])\s+(.+)$/) {
                blocks.append(.numbered(indent: indent, marker: String(match.output.1), text: String(match.output.2)))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }
        while blocks.last == .gap { blocks.removeLast() }
        return blocks
    }

    /// True when the text has any heading, bullet or numbered line, i.e. when formatting it changes anything.
    public static func hasStructure(_ text: String) -> Bool {
        parse(text).contains { block in
            if case .paragraph = block { return false }
            if case .gap = block { return false }
            return true
        }
    }
}
