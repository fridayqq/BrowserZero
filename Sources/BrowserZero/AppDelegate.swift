import AppKit
import BrowserZeroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var router: Router?
    private var picker: PickerPanel?

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
            self?.showPicker(url, source: source, state: state)
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

    /// One picker panel serves every link; a new link replaces what it shows.
    private func showPicker(_ url: URL, source: String?, state: AppState) {
        let panel = picker ?? PickerPanel()
        picker = panel
        panel.show(url: url, source: source, state: state)
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
