import ClipbackCore
import SwiftUI

/// Clipped text with its headings, bullets and line breaks kept. Plain text renders as before.
struct MarkdownText: View {
    let text: String
    var size: CGFloat = 14
    var design: Font.Design = .default
    var lineSpacing: CGFloat = 3
    /// Shows only the first few blocks, e.g. in a call agenda.
    var maxBlocks: Int?

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        let shown = maxBlocks.map { Array(blocks.prefix($0)) } ?? blocks
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: level <= 1 ? size + 3 : size + 1, weight: .semibold, design: design))
                .padding(.top, 2)
        case .bullet(let indent, let text):
            row(marker: indent == 0 ? "•" : "◦", text: text, indent: indent)
        case .numbered(let indent, let marker, let text):
            row(marker: marker, text: text, indent: indent)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: size, design: design))
                .lineSpacing(lineSpacing)
        case .gap:
            Color.clear.frame(height: 4)
        }
    }

    private func row(marker: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker).foregroundStyle(.secondary).frame(minWidth: 10, alignment: .trailing)
            Text(inline(text)).lineSpacing(lineSpacing)
        }
        .font(.system(size: size, design: design))
        .padding(.leading, CGFloat(indent) * 18)
    }

    /// Bold, italics, code and links inside a line; falls back to the plain text.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
