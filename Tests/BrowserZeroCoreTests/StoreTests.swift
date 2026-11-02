import Foundation
import Testing
@testable import BrowserZeroCore

private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("BrowserZero", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let chromeProfile = Target(
    browser: BrowserApp(bundleId: "com.google.Chrome", path: "/Applications/Chrome.app", name: "Chrome"),
    profile: Profile(kind: .chromiumProfile, name: "A", value: "Profile 1", icon: nil)
)

@Suite struct StoreTests {
    @Test func storeRoundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = Store(directory: directory)

        let config = Config(
            rules: [Rule(name: "X", pattern: "x.com", isRegex: false, sourceApps: ["com.apple.mail"], targetId: chromeProfile.id)],
            hiddenTargets: ["hidden|browser|"],
            hiddenBrowsers: ["com.example.Hidden"],
            cleanLinks: false,
            dismissedSuggestions: ["example.com"]
        )
        var history = History()
        history.record(host: "x.com", source: nil, targetId: chromeProfile.id, at: Date(timeIntervalSince1970: 1_800_000_000))
        let targets = [chromeProfile, Target(browser: chromeProfile.browser, profile: nil)]

        store.save(config)
        store.save(history)
        store.saveTargets(targets)

        #expect(store.loadConfig() == config)
        #expect(store.loadHistory().choices == history.choices)
        #expect(store.loadTargets() == targets)
    }

    @Test func missingFilesGiveDefaults() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = Store(directory: directory)

        #expect(store.loadConfig() == Config())
        #expect(store.loadHistory().choices.isEmpty)
        #expect(store.loadTargets().isEmpty)
    }

    @Test func corruptFilesGiveDefaults() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        for name in ["config.json", "history.json", "targets-cache.json"] {
            try Data("{oops".utf8).write(to: directory.appendingPathComponent(name))
        }
        let store = Store(directory: directory)

        #expect(store.loadConfig() == Config())
        #expect(store.loadHistory().choices.isEmpty)
        #expect(store.loadTargets().isEmpty)

        store.save(Config(cleanLinks: false))

        #expect(store.loadConfig().cleanLinks == false)
    }

    @Test func configToleratesMissingKeys() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"rules":[]}"#.utf8))

        #expect(config.cleanLinks == true)
        #expect(config.hiddenTargets.isEmpty)
        #expect(config.hiddenBrowsers.isEmpty)
        #expect(config.dismissedSuggestions.isEmpty)
    }
}
