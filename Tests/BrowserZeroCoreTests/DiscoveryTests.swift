import Foundation
import Testing
@testable import BrowserZeroCore

private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct DiscoveryTests {
    @Test func mozLz4RoundTrip() throws {
        let original = try fixture("zen-sessions", "json")
        let decoded = try #require(MozLz4.decode(MozLz4.encode(original)))
        #expect(decoded == original)
    }

    @Test func mozLz4RejectsBadMagic() {
        var bad = MozLz4.encode(Data("hello hello hello hello".utf8))
        bad[0] = 0x58
        #expect(MozLz4.decode(bad) == nil)
    }

    @Test func mozLz4RejectsWrongDeclaredSize() {
        var bad = MozLz4.encode(Data("hello hello hello hello".utf8))
        bad[8] = bad[8] &+ 1
        #expect(MozLz4.decode(bad) == nil)
    }

    @Test func mozLz4RejectsHugeDeclaredSize() {
        let huge = MozLz4.magic + Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data([0x00])
        #expect(MozLz4.decode(huge) == nil)
    }

    @Test func arcSpacesDeduped() throws {
        let profiles = try #require(ArcDiscovery.spaces(sidebarJSON: try fixture("arc-sidebar", "json")))
        #expect(profiles.map(\.name) == ["Personal", "Dev"])
        #expect(profiles.allSatisfy { $0.kind == .arcSpace && $0.value == $0.name })
    }

    @Test func arcInvalidShapeIsNil() {
        #expect(ArcDiscovery.spaces(sidebarJSON: Data(#"{"sidebar":{}}"#.utf8)) == nil)
    }

    @Test func zenProfilePathFromInstall() throws {
        let ini = String(decoding: try fixture("zen-profiles", "ini"), as: UTF8.self)
        #expect(ZenDiscovery.profilePath(iniText: ini) == "Profiles/4ata6ldq.Default (release)")
    }

    @Test func zenProfilePathFallsBackToDefaultSection() {
        let ini = "[Profile0]\nPath=/abs/x\nDefault=1\n"
        #expect(ZenDiscovery.profilePath(iniText: ini) == "/abs/x")
    }

    @Test func zenWorkspacesWithContainers() throws {
        let encoded = MozLz4.encode(try fixture("zen-sessions", "json"))
        let sessions = try #require(MozLz4.decode(encoded))
        let containers = try fixture("zen-containers", "json")
        let workspaces = try #require(ZenDiscovery.workspaces(sessionsJSON: sessions, containersJSON: containers))
        #expect(workspaces.map(\.name) == ["Personal", "Dev", "SL"])
        #expect(workspaces.map(\.value) == ["", "Work", ""])
        #expect(workspaces.map(\.icon) == ["🥷", "🌏️", "🏢"])
        #expect(workspaces.allSatisfy { $0.kind == .zenWorkspace })
    }

    @Test func zenWorkspacesIgnoreNonPublicAndUseCustomNames() throws {
        let sessions = Data(#"{"spaces":[{"name":"C","containerTabId":6},{"name":"H","containerTabId":7}]}"#.utf8)
        let containers = Data(#"{"identities":[{"userContextId":6,"public":true,"name":"Clients"},{"userContextId":7,"public":false,"name":"Hidden"}]}"#.utf8)
        let workspaces = try #require(ZenDiscovery.workspaces(sessionsJSON: sessions, containersJSON: containers))
        #expect(workspaces.map(\.value) == ["Clients", ""])
        #expect(workspaces.map(\.icon) == [nil, nil])
    }

    @Test func zenBuiltInNamesWithoutContainersFile() throws {
        let workspaces = try #require(ZenDiscovery.workspaces(
            sessionsJSON: try fixture("zen-sessions", "json"),
            containersJSON: nil
        ))
        #expect(workspaces.map(\.value) == ["", "Work", ""])
    }

    @Test func zenAddonDetected() throws {
        #expect(ZenDiscovery.isAddonInstalled(extensionsJSON: try fixture("zen-extensions", "json")))
        let inactive = Data(#"{"addons":[{"id":"x@y","active":false,"defaultLocale":{"name":"Open external links in a container"}}]}"#.utf8)
        #expect(ZenDiscovery.isAddonInstalled(extensionsJSON: inactive) == false)
        #expect(ZenDiscovery.isAddonInstalled(extensionsJSON: Data(#"{"addons":[]}"#.utf8)) == false)
    }

    @Test func zenPrefDetected() throws {
        let on = String(decoding: try fixture("zen-prefs", "js"), as: UTF8.self)
        #expect(ZenDiscovery.isForceContainerEnabled(prefsJS: on))
        let off = #"user_pref("zen.workspaces.force-container-workspace", false);"#
        #expect(ZenDiscovery.isForceContainerEnabled(prefsJS: off) == false)
    }

    @Test func chromiumProfilesOrdered() throws {
        let profiles = try #require(ChromiumDiscovery.profiles(localStateJSON: try fixture("chrome-local-state", "json")))
        #expect(profiles.map(\.name) == ["Person 1", "A"])
        #expect(profiles.map(\.value) == ["Default", "Profile 1"])
        #expect(profiles.allSatisfy { $0.kind == .chromiumProfile })
    }

    @Test func chromiumSingleProfileEmpty() {
        let single = Data(#"{"profile":{"info_cache":{"Default":{"name":"Person 1"}}}}"#.utf8)
        #expect(ChromiumDiscovery.profiles(localStateJSON: single) == [])
    }
}
