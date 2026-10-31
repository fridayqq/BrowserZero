import Foundation
import BrowserZeroCore

/// The app's model: user config, discovered targets, learned history and Zen setup.
@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var targets: [Target]
    @Published var history: History
    @Published var zenSetup = ZenSetup(addonInstalled: false, forceContainerEnabled: false, profileFound: false)

    let store: Store
    private let discovery: TargetDiscovery

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = Store(directory: appSupport.appendingPathComponent("BrowserZero", isDirectory: true))
        self.store = store
        self.discovery = TargetDiscovery(appSupport: appSupport)
        self.config = store.loadConfig()
        self.history = store.loadHistory()
        self.targets = store.loadTargets()
        refreshTargets()
    }

    /// Re-reads installed browsers, their profiles and Zen's setup in the background, then publishes and caches the result.
    func refreshTargets() {
        let discovery = self.discovery
        let previous = targets
        DispatchQueue.global(qos: .userInitiated).async {
            let browsers = Browsers.installed()
            let found = discovery.discover(browsers: browsers, previous: previous)
            let zen = discovery.zenSetup()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.targets = found
                    self.zenSetup = zen
                    self.store.saveTargets(found)
                }
            }
        }
    }

    /// Targets the user can pick: selectable, and neither hidden nor from a hidden browser.
    func visibleTargets() -> [Target] {
        targets.filter {
            $0.isSelectable
                && !config.hiddenTargets.contains($0.id)
                && !config.hiddenBrowsers.contains($0.browser.bundleId)
        }
    }

    func saveConfig() {
        store.save(config)
    }

    func record(host: String, source: String?, targetId: String) {
        history.record(host: host, source: source, targetId: targetId, at: Date())
        store.save(history)
    }
}
