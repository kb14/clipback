import AppKit
import SwiftUI

/// Walks through the two macOS permissions. Each row has three states: Allow (not asked yet), the steps to
/// finish in System Settings (asked), and Allowed. Nothing opens twice and the window doesn't reshuffle.
struct OnboardingView: View {
    var onDone: () -> Void
    var onOpenClipback: () -> Void

    @State private var granted: [Permission: Bool] = [:]
    @State private var asked: [Permission: Bool] = [:]
    /// Accessibility updates live, so it's checked every couple of seconds. Screen Recording only changes after
    /// a relaunch, so it's checked when the window appears or Clipback comes back to the front.
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(allGranted ? "Clipback is ready" : "Set up Clipback").font(.title2.weight(.semibold))
                Text(allGranted ? readyLine : "Clipback needs two permissions to capture from other apps. Your clips stay on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Permission.allCases) { permission in
                    row(permission)
                    if permission != Permission.allCases.last { Divider() }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if allGranted {
                    Button("Done", action: onDone)
                    Button("Open Clipback", action: onOpenClipback)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .onAppear {
            asked = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, $0.hasAsked) })
            refresh(includingScreenRecording: true)
        }
        .onReceive(poll) { _ in refresh(includingScreenRecording: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh(includingScreenRecording: true)
        }
    }

    private var allGranted: Bool { Permission.allCases.allSatisfy { granted[$0] == true } }

    private var readyLine: String {
        let hotkey = Hotkeys.captureTitle.map { " and press \($0)" } ?? ""
        return "Select text in any app\(hotkey) to clip it. With nothing selected, you can drag over a region of the screen."
    }

    private func row(_ permission: Permission) -> some View {
        let isGranted = granted[permission] == true
        let hasAsked = asked[permission] == true
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title).font(.body.weight(.medium))
                Text(permission.reason).font(.callout).foregroundStyle(.secondary)
                if !isGranted && hasAsked {
                    steps(for: permission)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 12)
            Group {
                if isGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else if hasAsked {
                    Button("Open System Settings") { permission.openSettings() }
                } else {
                    Button("Allow") { ask(permission) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
    }

    @ViewBuilder
    private func steps(for permission: Permission) -> some View {
        switch permission {
        case .accessibility:
            Text("Turn on **Clipback** under Privacy & Security → Accessibility. This page updates on its own.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        case .screenRecording:
            // macOS prompts only once, and after that may not list the app by itself (tccd: "does not allow
            // prompting"), so the steps cover adding it by hand.
            VStack(alignment: .leading, spacing: 8) {
                Text("""
                    In **Screen & System Audio Recording**, turn on **Clipback**. If it isn't in the list, click \
                    **+** and choose it, or drag it in from Finder. Then choose **Quit & Reopen** when macOS asks.
                    """)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Show Clipback in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    Button("Relaunch Clipback") { Permission.relaunch() }
                }
                .controlSize(.small)
            }
        }
    }

    private func ask(_ permission: Permission) {
        asked[permission] = true
        Task { await permission.request() }
    }

    private func refresh(includingScreenRecording: Bool) {
        for permission in Permission.allCases where permission == .accessibility || includingScreenRecording {
            let now = permission.isGranted
            if granted[permission] != now { granted[permission] = now }
        }
        // Screen Recording only takes effect after macOS's Quit & Reopen. While this window shows it off, however
        // it then gets turned on (Allow, System Settings, macOS's own dialog), the next launch brings this window
        // back as "Clipback is ready". Once everything is green here, there's nothing left to announce.
        Permission.awaitingReady = !allGranted && granted[.screenRecording] != true
    }
}
