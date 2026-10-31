import AppKit
import SwiftUI
import BrowserZeroCore

/// Owns the single Settings window. The window is created on first `show()` and reused afterwards.
@MainActor
final class SettingsWindowController {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Browser Zero Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(state: state))
        window.center()
        return window
    }
}

/// The three settings tabs.
struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            GeneralTab(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            TargetsTab(state: state)
                .tabItem { Label("Targets", systemImage: "rectangle.stack") }
            RulesTab(state: state)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 720, height: 520)
    }
}

extension AppState {
    /// Applies one change to the config, then persists it.
    func update(_ change: (inout Config) -> Void) {
        change(&config)
        saveConfig()
    }
}
