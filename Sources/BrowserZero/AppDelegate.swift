import AppKit
import BrowserZeroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var router: Router?
    private var picker: PickerPanel?
    /// Links that arrived while the picker was visible; shown one at a time, first in first out.
    private var queuedLinks: [(url: URL, source: String?)] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state
        router = Router(state: state) { [weak self] url, source in
            // With no picker target, fall back to a plain browser so the link is never lost.
            guard !state.visibleTargets().isEmpty else {
                guard let target = Browsers.fallbackTarget() else {
                    NSLog("Browser Zero: no browser available for \(url.absoluteString)")
                    return
                }
                Opener.open([url], target: target, zenSetup: state.zenSetup)
                return
            }
            self?.showPicker(url, source: source)
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
        menu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    /// Shows the picker for a link. While it is visible, the link waits in the queue instead.
    private func showPicker(_ url: URL, source: String?) {
        guard let state else { return }
        if let picker, picker.isVisible {
            queuedLinks.append((url: url, source: source))
            return
        }
        let panel = picker ?? makePicker()
        picker = panel
        panel.show(url: url, source: source, state: state)
    }

    private func makePicker() -> PickerPanel {
        let panel = PickerPanel()
        panel.onClose = { [weak self] in
            DispatchQueue.main.async { self?.showNextQueuedLink() }
        }
        return panel
    }

    private func showNextQueuedLink() {
        guard !queuedLinks.isEmpty else { return }
        let next = queuedLinks.removeFirst()
        showPicker(next.url, source: next.source)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            router?.handle(url, sourceApp: nil, forcePicker: false)
        }
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
