import ClipbackCore
import SwiftUI

struct CapturePanelView: View {
    @Bindable var draft: CaptureDraft
    var onSizeChange: (CGSize) -> Void

    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if draft.kind == .text { quote } else { thumbnail }
            noteField
            if !draft.suggestions.isEmpty {
                suggestionList
            } else if !draft.people.isEmpty || !draft.tags.isEmpty {
                chips
            }
            footer
        }
        .padding(14)
        .frame(width: 560, alignment: .leading)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .onAppear { noteFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = draft.context.appIcon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(draft.sourceLine)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button(action: draft.toggleLibrary) {
                HStack(spacing: 5) {
                    Circle().fill(draft.library.color).frame(width: 7, height: 7)
                    Text(draft.library.title)
                    KeyHint("⌘L")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
    }

    private var quote: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1).fill(Color.highlight).frame(width: 2.5)
            Text(draft.selection.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thumbnail: some View {
        HStack(alignment: .center, spacing: 12) {
            if let image = draft.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 140, maxHeight: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.kind == .window ? "Window" : "Region")
                    .font(.system(size: 12, weight: .medium))
                Group {
                    if draft.isReadingText {
                        Text("Reading text…")
                    } else if let text = draft.ocrText, !text.isEmpty {
                        Text("Text found: \(text.replacingOccurrences(of: "\n", with: " "))").lineLimit(2)
                    } else {
                        Text("No text found")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var noteField: some View {
        TextField("Add a note   @person   #tag", text: $draft.note)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($noteFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var suggestionList: some View {
        let sigil = NoteParser.trailingToken(in: draft.note)?.sigil ?? "@"
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(draft.suggestions.enumerated()), id: \.offset) { index, suggestion in
                let isOn = index == draft.highlightedSuggestion
                HStack(spacing: 10) {
                    Text("\(String(sigil))\(suggestion.value)")
                    if let detail = suggestion.detail {
                        Text(detail).lineLimit(1).opacity(0.7)
                    }
                    Spacer()
                    Text(sigil == "@" ? "Call" : "Tag").font(.system(size: 11)).opacity(0.7)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    draft.highlightedSuggestion = index
                    _ = draft.acceptSuggestion()
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var chips: some View {
        HStack(spacing: 5) {
            ForEach(draft.people, id: \.self) { person in
                Chip(text: "@\(person)", tint: Intent.call.color)
            }
            ForEach(draft.tags, id: \.self) { tag in
                Chip(text: "#\(tag)", tint: nil)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Array(Intent.allCases.enumerated()), id: \.element) { index, intent in
                    IntentButton(intent: intent, number: index + 1, isOn: draft.intent == intent) {
                        draft.intent = intent
                    }
                }
            }
            .padding(2)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 4) { KeyHint("↩"); Text("save") }
                HStack(spacing: 4) { KeyHint("esc"); Text("discard") }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
        }
    }
}

private struct IntentButton: View {
    let intent: Intent
    let number: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(intent.color).frame(width: 7, height: 7)
                Text(intent.title)
                Text("⌘\(number)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .foregroundStyle(isOn ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Chip: View {
    let text: String
    let tint: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .foregroundStyle(tint ?? .secondary)
            .background((tint ?? .secondary).opacity(0.14), in: Capsule())
    }
}

private struct KeyHint: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5))
    }
}
