import AppKit
import BrowserZeroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var router: Router?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state
        router = Router(state: state) { url, _ in
            // Temporary until the picker exists: open in the first visible target, else a fallback browser.
            guard let target = state.visibleTargets().first ?? Browsers.fallbackTarget() else {
                NSLog("Browser Zero: no browser available for \(url.absoluteString)")
                return
            }
            Opener.open([url], target: target, zenSetup: state.zenSetup)
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
