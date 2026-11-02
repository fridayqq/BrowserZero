import AppKit
import ServiceManagement
import SwiftUI
import BrowserZeroCore

/// Whether macOS routes web links to this app.
enum DefaultBrowser {
    static var isSelf: Bool {
        guard let https = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: https)
        else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

struct GeneralTab: View {
    @ObservedObject var state: AppState
    @State private var isDefault = DefaultBrowser.isSelf
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var defaultError: String?
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Default browser") {
                HStack {
                    Text(isDefault ? "Browser Zero is the default browser" : "Another app is the default browser")
                    Spacer()
                    Button("Set as Default Browser") { setDefault() }
                        .disabled(isDefault)
                }
                if let defaultError {
                    Text(defaultError).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Links") {
                Toggle("Clean links (remove redirects and tracking parameters)", isOn: Binding(
                    get: { state.config.cleanLinks },
                    set: { value in state.update { $0.cleanLinks = value } }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatus)
    }

    private func refreshStatus() {
        isDefault = DefaultBrowser.isSelf
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setDefault() {
        let appURL = Bundle.main.bundleURL
        Task { @MainActor in
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
                defaultError = nil
            } catch {
                defaultError = error.localizedDescription
            }
            isDefault = DefaultBrowser.isSelf
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
