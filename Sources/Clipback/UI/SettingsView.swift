import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var onReviewPermissions: () -> Void

    @State private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status != .notRegistered
    @State private var launchStatus = SMAppService.mainApp.status
    @State private var launchError: String?
    @State private var workRules = AppSettings.shared.workRules.joined(separator: ", ")

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Capture", name: .capture)
                KeyboardShortcuts.Recorder("Open Clipback", name: .openClipback)
            }

            Section("Clips folder") {
                HStack {
                    Text(settings.vaultURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(settings.vaultURL) }
                    Button("Change…", action: chooseVault)
                }
            }

            Section {
                TextField("Always Work", text: $workRules, prompt: Text("Slack, acme.com"))
                    .onChange(of: workRules) { _, text in
                        settings.workRules = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
            } header: {
                Text("Work library")
            } footer: {
                Text("Apps, or words in a page address, window title or file path, separated by commas. Clips from these start in Work at any time of day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("General") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if launchAtLogin && launchStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs you to allow Clipback in Login Items before it starts at login.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let launchError {
                    Text(launchError).font(.callout).foregroundStyle(.red)
                }
                Button("Review permissions…", action: onReviewPermissions)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchStatus = SMAppService.mainApp.status
        }
        .frame(width: 520, height: 520)
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.directoryURL = settings.vaultURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultURL = url
        Vault.bootstrap()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            UserDefaults.clipback.set(enabled ? Bundle.main.bundlePath : nil, forKey: LoginItem.registeredPathKey)
            launchError = nil
            launchStatus = SMAppService.mainApp.status
            if enabled && launchStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            launchError = "Couldn't change this: \(error.localizedDescription)"
            launchStatus = SMAppService.mainApp.status
            launchAtLogin = launchStatus != .notRegistered
        }
    }
}
