import AppKit
import BrowserZeroCore

/// Browsers that can receive links: every installed app that claims `https` and lives in a system or
/// user Applications folder, minus apps that are not browsers in practice (terminals, AI chat apps,
/// Browser Zero itself, Browserino).
enum Browsers {
    private static let excludedBundleIds: Set<String> = [
        "com.googlecode.iterm2",
        "com.openai.chat",
        "com.openai.codex",
        "com.apple.Terminal",
        "xyz.alexstrnik.Browserino",
    ]

    private static let safariBundleId = "com.apple.Safari"

    static func installed() -> [BrowserApp] {
        guard let https = URL(string: "https://example.com") else { return [] }
        let ownBundleId = Bundle.main.bundleIdentifier
        let allowedPrefixes = ["/Applications/", "/System/", NSHomeDirectory() + "/Applications/"]

        var byId: [String: BrowserApp] = [:]
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: https) {
            guard allowedPrefixes.contains(where: { appURL.path.hasPrefix($0) }) else { continue }
            guard let bundleId = Bundle(url: appURL)?.bundleIdentifier,
                  bundleId != ownBundleId,
                  !excludedBundleIds.contains(bundleId)
            else { continue }

            let candidate = BrowserApp(
                bundleId: bundleId,
                path: appURL.path,
                name: FileManager.default.displayName(atPath: appURL.path)
            )
            if let existing = byId[bundleId], !prefers(candidate, over: existing) { continue }
            byId[bundleId] = candidate
        }

        if byId[safariBundleId] == nil,
           let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariBundleId) {
            byId[safariBundleId] = BrowserApp(
                bundleId: safariBundleId,
                path: safariURL.path,
                name: FileManager.default.displayName(atPath: safariURL.path)
            )
        }

        return byId.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A plain target for links that no visible target can take: Safari when installed, else the first browser.
    static func fallbackTarget() -> Target? {
        let browsers = installed()
        let browser = browsers.first { $0.bundleId == safariBundleId } ?? browsers.first
        return browser.map { Target(browser: $0, profile: nil) }
    }

    /// Duplicates of one bundle id (e.g. the same app in several folders): the copy in /Applications wins.
    private static func prefers(_ candidate: BrowserApp, over existing: BrowserApp) -> Bool {
        candidate.path.hasPrefix("/Applications/") && !existing.path.hasPrefix("/Applications/")
    }
}
