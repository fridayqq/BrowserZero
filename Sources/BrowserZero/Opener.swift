import AppKit
import BrowserZeroCore

/// Opens links in a browser, or in one of its profiles (Arc space, Zen workspace, Chromium profile).
enum Opener {
    /// Arc's AppleScript must run off the main thread; serial so tabs keep their order.
    private static let scriptQueue = DispatchQueue(label: "app.browserzero.applescript")

    static func open(_ urls: [URL], target: Target, zenSetup: ZenSetup) {
        let appURL = URL(fileURLWithPath: target.browser.path)
        guard let profile = target.profile, !profile.value.isEmpty else {
            openPlain(urls, app: appURL)
            return
        }

        switch profile.kind {
        case .arcSpace:
            openInArc(urls, space: profile.value, fallbackApp: appURL)
        case .zenWorkspace:
            guard zenSetup.addonInstalled && zenSetup.forceContainerEnabled else {
                openPlain(urls, app: appURL)
                return
            }
            let containerURLs = urls.map { ScriptBuilder.zenContainerURL(container: profile.value, url: $0) }
            openPlain(containerURLs, app: appURL)
        case .chromiumProfile:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ScriptBuilder.chromiumArguments(profileDir: profile.value, urls: urls)
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    private static func openPlain(_ urls: [URL], app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func openInArc(_ urls: [URL], space: String, fallbackApp: URL) {
        let source = ScriptBuilder.arcScript(space: space, urls: urls)
        scriptQueue.async {
            var error: NSDictionary?
            let succeeded = NSAppleScript(source: source)?.executeAndReturnError(&error) != nil && error == nil
            guard !succeeded else { return }
            NSLog("Browser Zero: Arc AppleScript failed: \(String(describing: error))")
            // Never lose the link: open it in Arc without the space.
            DispatchQueue.main.async {
                openPlain(urls, app: fallbackApp)
            }
        }
    }
}
