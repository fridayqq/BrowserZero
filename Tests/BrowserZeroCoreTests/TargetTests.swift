import Testing
@testable import BrowserZeroCore

private let arc = BrowserApp(bundleId: "company.thebrowser.Browser", path: "/Applications/Arc.app", name: "Arc")

@Suite struct TargetTests {
    @Test func targetIdForPlainBrowser() {
        let target = Target(browser: arc, profile: nil)
        #expect(target.id == "company.thebrowser.Browser|browser|")
    }

    @Test func targetIdForProfile() {
        let profile = Profile(kind: .arcSpace, name: "Dev", value: "Dev", icon: nil)
        let target = Target(browser: arc, profile: profile)
        #expect(target.id == "company.thebrowser.Browser|arcSpace|Dev")
        #expect(target.displayName == "Arc · Dev")
    }

    @Test func zenWithoutContainerNotSelectable() {
        let profile = Profile(kind: .zenWorkspace, name: "SL", value: "", icon: "🏢")
        let target = Target(browser: BrowserApp(bundleId: "app.zen-browser.zen", path: "/Applications/Zen.app", name: "Zen"), profile: profile)
        #expect(target.isSelectable == false)
    }
}
