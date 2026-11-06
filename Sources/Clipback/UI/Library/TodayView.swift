import ClipbackCore
import SwiftUI

/// Revise clips coming back today, one card at a time. A shows it again tomorrow, Space moves it further out,
/// R retires it.
struct TodayView: View {
    let library: ClipLibrary
    /// Off while typing in search, so letters don't answer the card.
    var keysEnabled = true

    var body: some View {
        let today = library.today(in: library.library)
        ScrollView {
            VStack(spacing: 18) {
                header(today)
                if let stored = today.due.first {
                    ReviewCard(stored: stored)
                        .id(stored.id)
                    answers(for: stored)
                } else {
                    caughtUp(today)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Today")
    }

    private func header(_ today: ReviewQueue.Today<StoredClip>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Today").font(.title.weight(.semibold))
            if !today.due.isEmpty {
                Text("\(today.reviewedToday + 1) of \(today.total)").foregroundStyle(.tertiary)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<(today.total > 1 ? today.total : 0), id: \.self) { index in
                    Capsule()
                        .fill(index < today.reviewedToday ? Intent.revise.color : Color.secondary.opacity(0.25))
                        .frame(width: 22, height: 4)
                }
            }
        }
    }

    private func answers(for stored: StoredClip) -> some View {
        let state = stored.clip.review ?? ReviewState.initial(after: stored.clip.created)
        let gotItDays = ReviewScheduler.daysAfterGotIt(state)
        return HStack(spacing: 10) {
            AnswerButton(title: "Again", detail: "A · tomorrow", key: "a", keysEnabled: keysEnabled) { library.answer(stored, .again) }
            AnswerButton(title: "Got it", detail: "Space · in \(gotItDays) days", key: .space, keysEnabled: keysEnabled, isPrimary: true) {
                library.answer(stored, .gotIt)
            }
            AnswerButton(title: "Retire", detail: "R · stop showing", key: "r", keysEnabled: keysEnabled) { library.answer(stored, .retire) }
        }
    }

    private func caughtUp(_ today: ReviewQueue.Today<StoredClip>) -> some View {
        let rotation = library.activeClips.filter { $0.clip.intent == .revise }
        let next = rotation.compactMap(\.clip.review).filter { $0.daysUntilNext() > 0 }.min { $0.next < $1.next }
        return VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(Intent.revise.color)
            Text(today.reviewedToday > 0 ? "All caught up" : "Nothing to revise today")
                .font(.title3.weight(.semibold))
            Group {
                if rotation.isEmpty {
                    Text("Mark a clip Revise (⌘2 in the capture panel) and it comes back here tomorrow, then after 3, 7, 16, 35 and 75 days.")
                } else if let next {
                    Text("\(rotation.count) \(rotation.count == 1 ? "clip" : "clips") in rotation. The next one comes back \(next.whenNext()).")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 420)
        }
        .padding(.top, 60)
    }
}

private struct ReviewCard: View {
    let stored: StoredClip
    @State private var showsContext = false

    private var clip: Clip { stored.clip }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcons.icon(bundleID: clip.source.bundleID, appName: clip.source.app))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(SourceLabel.short(clip.source)).lineLimit(1)
                Spacer()
                Text(clip.tags.map { "#\($0)" }.joined(separator: "  ")).lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            if clip.kind == .text {
                MarkdownText(text: clip.selection, size: 19, design: .serif, lineSpacing: 5)
                    .textSelection(.enabled)
            } else if let url = stored.imageURL, let image = NSImage(contentsOf: url) {
                LiveTextImage(image: image)
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !clip.note.isEmpty {
                Divider()
                (Text("Your note  ").fontWeight(.medium).foregroundStyle(.primary) + Text(clip.note))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            if clip.before != nil || clip.after != nil {
                DisclosureGroup("Show context", isExpanded: $showsContext) {
                    (Text(clip.before ?? "") + Text(clip.selection).foregroundStyle(.primary) + Text(clip.after ?? ""))
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            }

            if SourceOpener.canOpen(clip.source) {
                Button {
                    SourceOpener.open(clip.source)
                } label: {
                    Label(SourceOpener.label(clip.source), systemImage: "arrow.up.forward.square")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

private struct AnswerButton: View {
    let title: String
    let detail: String
    let key: KeyEquivalent
    let keysEnabled: Bool
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 11)).opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .background(isPrimary ? Intent.revise.color : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keysEnabled ? KeyboardShortcut(key, modifiers: []) : nil)
    }
}
