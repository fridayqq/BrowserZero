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

    /// True while a background refresh is running. Overlapping requests are coalesced into the running one.
    private(set) var isRefreshing = false
    /// Callbacks waiting for the running refresh to publish its result.
    private var refreshWaiters: [() -> Void] = []

    /// Re-reads installed browsers, their profiles and Zen's setup in the background, then publishes and caches the result.
    func refreshTargets() {
        guard !isRefreshing else { return }
        isRefreshing = true
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
                    self.isRefreshing = false
                    let waiters = self.refreshWaiters
                    self.refreshWaiters = []
                    waiters.forEach { $0() }
                }
            }
        }
    }

    /// Runs `body` as soon as no refresh is running, or after `maxWait` at the latest. Runs it at once when idle.
    func afterRefresh(maxWait: Duration, _ body: @escaping () -> Void) {
        guard isRefreshing else {
            body()
            return
        }
        var finished = false
        let finish: () -> Void = {
            guard !finished else { return }
            finished = true
            body()
        }
        refreshWaiters.append(finish)
        Task {
            try? await Task.sleep(for: maxWait)
            finish()
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
