import Foundation

public enum ProfileKind: String, Codable, Sendable {
    case arcSpace
    case zenWorkspace
    case chromiumProfile
}

/// A sub-target inside a browser: an Arc space, a Zen workspace or a Chromium profile.
public struct Profile: Codable, Hashable, Sendable {
    public var kind: ProfileKind
    /// Display name (space / workspace / profile name).
    public var name: String
    /// Arc: space title. Zen: container name. Chromium: profile directory.
    /// Empty means the profile cannot be targeted.
    public var value: String
    /// Optional emoji icon (Zen workspaces).
    public var icon: String?

    public init(kind: ProfileKind, name: String, value: String, icon: String?) {
        self.kind = kind
        self.name = name
        self.value = value
        self.icon = icon
    }
}

public struct BrowserApp: Codable, Hashable, Sendable {
    public var bundleId: String
    public var path: String
    public var name: String

    public init(bundleId: String, path: String, name: String) {
        self.bundleId = bundleId
        self.path = path
        self.name = name
    }
}

/// A browser, optionally narrowed to one of its profiles, that a link can be opened in.
public struct Target: Codable, Hashable, Identifiable, Sendable {
    public var browser: BrowserApp
    public var profile: Profile?

    public init(browser: BrowserApp, profile: Profile?) {
        self.browser = browser
        self.profile = profile
    }

    public var id: String {
        "\(browser.bundleId)|\(profile?.kind.rawValue ?? "browser")|\(profile?.name ?? "")"
    }

    public var isSelectable: Bool {
        profile == nil || !(profile?.value.isEmpty ?? true)
    }

    public var displayName: String {
        guard let profile else { return browser.name }
        return "\(browser.name) · \(profile.name)"
    }
}
