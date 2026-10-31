import Foundation
import Testing
@testable import BrowserZeroCore

private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private let arc = BrowserApp(bundleId: "company.thebrowser.Browser", path: "/Applications/Arc.app", name: "Arc")
private let zen = BrowserApp(bundleId: "app.zen-browser.zen", path: "/Applications/Zen.app", name: "Zen")
private let chrome = BrowserApp(bundleId: "com.google.Chrome", path: "/Applications/Chrome.app", name: "Chrome")
private let zenProfileFolder = "zen/Profiles/4ata6ldq.Default (release)"

/// Writes Arc, Zen and Chrome data into `root` the way the real apps lay it out.
private func populate(_ root: URL, chromeLocalState: Data? = nil) throws {
    try write(try fixture("arc-sidebar", "json"), to: root.appendingPathComponent("Arc/StorableSidebar.json"))
    try write(try fixture("zen-profiles", "ini"), to: root.appendingPathComponent("zen/profiles.ini"))
    let profileDir = root.appendingPathComponent(zenProfileFolder, isDirectory: true)
    try write(MozLz4.encode(try fixture("zen-sessions", "json")), to: profileDir.appendingPathComponent("zen-sessions.jsonlz4"))
    try write(try fixture("zen-containers", "json"), to: profileDir.appendingPathComponent("containers.json"))
    try write(
        try chromeLocalState ?? fixture("chrome-local-state", "json"),
        to: root.appendingPathComponent("Google/Chrome/Local State")
    )
}

@Suite struct TargetDiscoveryTests {
    @Test func discoversArcZenChromium() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try populate(root)

        let targets = TargetDiscovery(appSupport: root).discover(browsers: [arc, zen, chrome], previous: [])

        #expect(targets.map(\.id) == [
            "company.thebrowser.Browser|browser|",
            "company.thebrowser.Browser|arcSpace|Personal",
            "company.thebrowser.Browser|arcSpace|Dev",
            "app.zen-browser.zen|browser|",
            "app.zen-browser.zen|zenWorkspace|Personal",
            "app.zen-browser.zen|zenWorkspace|Dev",
            "app.zen-browser.zen|zenWorkspace|SL",
            "com.google.Chrome|browser|",
            "com.google.Chrome|chromiumProfile|Person 1",
            "com.google.Chrome|chromiumProfile|A",
        ])
        let sl = try #require(targets.first { $0.id == "app.zen-browser.zen|zenWorkspace|SL" })
        #expect(sl.isSelectable == false)
    }

    @Test func unreadableKeepsPrevious() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try populate(root, chromeLocalState: Data("{oops".utf8))
        let previous = Target(
            browser: chrome,
            profile: Profile(kind: .chromiumProfile, name: "A", value: "Profile 1", icon: nil)
        )

        let targets = TargetDiscovery(appSupport: root).discover(browsers: [chrome], previous: [previous])

        #expect(targets == [Target(browser: chrome, profile: nil), previous])
    }

    @Test func missingSourceGivesPlainOnly() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = Target(
            browser: chrome,
            profile: Profile(kind: .chromiumProfile, name: "A", value: "Profile 1", icon: nil)
        )

        let targets = TargetDiscovery(appSupport: root).discover(browsers: [chrome], previous: [previous])

        #expect(targets == [Target(browser: chrome, profile: nil)])
    }

    @Test func zenSetupFlags() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try populate(root)
        let profileDir = root.appendingPathComponent(zenProfileFolder, isDirectory: true)
        try write(try fixture("zen-extensions", "json"), to: profileDir.appendingPathComponent("extensions.json"))
        try write(try fixture("zen-prefs", "js"), to: profileDir.appendingPathComponent("prefs.js"))

        let setup = TargetDiscovery(appSupport: root).zenSetup()

        #expect(setup == ZenSetup(addonInstalled: true, forceContainerEnabled: true, profileFound: true))
    }

    @Test func zenSetupWithoutExtensionsOrPrefs() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(try fixture("zen-profiles", "ini"), to: root.appendingPathComponent("zen/profiles.ini"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(zenProfileFolder, isDirectory: true),
            withIntermediateDirectories: true
        )

        let setup = TargetDiscovery(appSupport: root).zenSetup()

        #expect(setup == ZenSetup(addonInstalled: false, forceContainerEnabled: false, profileFound: true))
    }

    @Test func zenSetupWithoutProfile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let setup = TargetDiscovery(appSupport: root).zenSetup()

        #expect(setup == ZenSetup(addonInstalled: false, forceContainerEnabled: false, profileFound: false))
    }

    @Test func zenProfileDirectoryResolvesRelativePath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(try fixture("zen-profiles", "ini"), to: root.appendingPathComponent("zen/profiles.ini"))

        let dir = try #require(TargetDiscovery(appSupport: root).zenProfileDirectory())

        #expect(dir.path == root.appendingPathComponent(zenProfileFolder, isDirectory: true).path)
    }
}
