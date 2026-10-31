import AppKit
import BrowserZeroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var router: Router?
    private var picker: PickerPanel?
    private var settings: SettingsWindowController?
    /// Links that arrived while the picker was visible; shown one at a time, first in first out.
    private var queuedLinks: [(url: URL, source: String?)] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state
        settings = SettingsWindowController(state: state)
        // An accessory app has no menu bar, but its main menu still carries the ⌘, shortcut for Settings.
        NSApp.mainMenu = makeMainMenu()
        router = Router(state: state) { [weak self] url, source in
            // On a fresh install the first link can arrive before discovery finishes, so give it a moment.
            guard state.visibleTargets().isEmpty, state.isRefreshing else {
                self?.route(url, source: source, state: state)
                return
            }
            state.afterRefresh(maxWait: .seconds(2)) { [weak self] in
                self?.route(url, source: source, state: state)
            }
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Browser Zero")
        }

        let menu = NSMenu()
        menu.addItem(settingsMenuItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    /// Opening the app again (e.g. from Finder) shows Settings, since there is no other window to show.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return true
    }

    @objc private func openSettings() {
        settings?.show()
    }

    private func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(settingsMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Browser Zero", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        return mainMenu
    }

    /// Queues a link behind any waiting ones, then shows the oldest if the picker is free.
    /// Links never jump the queue, even one arriving while the previous picker is still closing.
    private func showPicker(_ url: URL, source: String?) {
        queuedLinks.append((url: url, source: source))
        showNextQueuedLinkIfIdle()
    }

    private func showNextQueuedLinkIfIdle() {
        guard let state, picker?.isVisible != true, !queuedLinks.isEmpty else { return }
        // Refresh so the picker about to show reflects browsers and profiles added since the last one.
        state.refreshTargets()
        let next = queuedLinks.removeFirst()
        guard !state.visibleTargets().isEmpty else {
            openWithFallback(next.url, state: state)
            showNextQueuedLinkIfIdle()
            return
        }
        let panel = picker ?? makePicker()
        picker = panel
        panel.show(url: next.url, source: next.source, state: state)
    }

    /// Shows the picker when some target can take the link, otherwise opens it in a plain browser.
    private func route(_ url: URL, source: String?, state: AppState) {
        guard !state.visibleTargets().isEmpty else {
            openWithFallback(url, state: state)
            return
        }
        showPicker(url, source: source)
    }

    /// With no picker target, a plain browser takes the link so it is never lost.
    private func openWithFallback(_ url: URL, state: AppState) {
        guard let target = Browsers.fallbackTarget() else {
            NSLog("Browser Zero: no browser available for \(url.absoluteString)")
            return
        }
        Opener.open([url], target: target, zenSetup: state.zenSetup)
    }

    private func makePicker() -> PickerPanel {
        let panel = PickerPanel()
        panel.onClose = { [weak self] in
            DispatchQueue.main.async { self?.showNextQueuedLinkIfIdle() }
        }
        return panel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            router?.handle(url, sourceApp: nil, forcePicker: false)
        }
    }

    /// Handoff: a browsing activity from another device (Safari, Handoff) arrives as a web page URL.
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        userActivityType == NSUserActivityTypeBrowsingWeb
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
            return false
        }
        router?.handle(url, sourceApp: nil, forcePicker: false)
        return true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        guard let url = URL(string: string)
            ?? string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        else {
            NSLog("Browser Zero: dropped unparseable URL: \(string)")
            return
        }

        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let sourceApp = pid.flatMap { SourceApp.bundleId(forPID: $0) }
        let forcePicker = NSEvent.modifierFlags.contains(.option)
        router?.handle(url, sourceApp: sourceApp, forcePicker: forcePicker)
    }
}
