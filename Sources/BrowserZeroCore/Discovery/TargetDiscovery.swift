import Foundation

/// Whether Zen's profile is set up for Browser Zero's link routing.
public struct ZenSetup: Codable, Hashable, Sendable {
    public var addonInstalled: Bool
    public var forceContainerEnabled: Bool
    public var profileFound: Bool

    public init(addonInstalled: Bool, forceContainerEnabled: Bool, profileFound: Bool) {
        self.addonInstalled = addonInstalled
        self.forceContainerEnabled = forceContainerEnabled
        self.profileFound = profileFound
    }
}

/// Reads each browser's on-disk profile data under an Application Support directory.
public struct TargetDiscovery: Sendable {
    private enum Source {
        /// The data file does not exist: the browser has no profiles.
        case missing
        /// The file exists but cannot be read or parsed: keep the previously known profiles.
        case unreadable
        case profiles([Profile])
    }

    private enum Read {
        case missing
        case unreadable
        case data(Data)
    }

    private let appSupport: URL

    public init(appSupport: URL) {
        self.appSupport = appSupport
    }

    /// One plain target per browser, followed by its profile targets in parser order.
    /// A browser whose profile data cannot be read keeps its profile targets from `previous`.
    public func discover(browsers: [BrowserApp], previous: [Target]) -> [Target] {
        browsers.flatMap { browser -> [Target] in
            let plain = Target(browser: browser, profile: nil)
            switch profiles(for: browser) {
            case .missing:
                return [plain]
            case .unreadable:
                let kept = previous.filter { $0.browser.bundleId == browser.bundleId && $0.profile != nil }
                return [plain] + kept
            case .profiles(let found):
                return [plain] + found.map { Target(browser: browser, profile: $0) }
            }
        }
    }

    /// Zen's setup flags for the profile in `profiles.ini`. Missing files count as not set up.
    public func zenSetup() -> ZenSetup {
        guard let directory = zenProfileDirectory() else {
            return ZenSetup(addonInstalled: false, forceContainerEnabled: false, profileFound: false)
        }
        var isDirectory = ObjCBool(false)
        let profileFound = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue

        let addonInstalled = data(directory.appendingPathComponent("extensions.json"))
            .map { ZenDiscovery.isAddonInstalled(extensionsJSON: $0) } ?? false
        let forceContainerEnabled = data(directory.appendingPathComponent("prefs.js"))
            .map { ZenDiscovery.isForceContainerEnabled(prefsJS: String(decoding: $0, as: UTF8.self)) } ?? false

        return ZenSetup(
            addonInstalled: addonInstalled,
            forceContainerEnabled: forceContainerEnabled,
            profileFound: profileFound
        )
    }

    /// The Zen profile directory named by `profiles.ini`, resolved against `zen/` when relative.
    /// Returns nil when `profiles.ini` is missing or names no profile.
    public func zenProfileDirectory() -> URL? {
        guard let path = zenProfilePath() else { return nil }
        return profileDirectory(path)
    }

    // MARK: - Per-browser sources

    private func profiles(for browser: BrowserApp) -> Source {
        switch browser.bundleId {
        case ArcDiscovery.bundleId:
            return parse(appSupport.appendingPathComponent("Arc/StorableSidebar.json")) {
                ArcDiscovery.spaces(sidebarJSON: $0)
            }
        case ZenDiscovery.bundleId:
            return zenProfiles()
        default:
            guard let folder = ChromiumDiscovery.dataDirs[browser.bundleId] else { return .missing }
            return parse(appSupport.appendingPathComponent("\(folder)/Local State")) {
                ChromiumDiscovery.profiles(localStateJSON: $0)
            }
        }
    }

    private func zenProfiles() -> Source {
        let iniURL = zenRoot.appendingPathComponent("profiles.ini")
        let iniData: Data
        switch read(iniURL) {
        case .missing: return .missing
        case .unreadable: return .unreadable
        case .data(let data): iniData = data
        }
        guard let path = ZenDiscovery.profilePath(iniText: String(decoding: iniData, as: UTF8.self)) else {
            return .unreadable
        }

        let directory = profileDirectory(path)
        return parse(directory.appendingPathComponent("zen-sessions.jsonlz4")) { data in
            guard let sessions = MozLz4.decode(data) else { return nil }
            let containers = try? Data(contentsOf: directory.appendingPathComponent("containers.json"))
            return ZenDiscovery.workspaces(sessionsJSON: sessions, containersJSON: containers)
        }
    }

    private func parse(_ url: URL, _ parser: (Data) -> [Profile]?) -> Source {
        switch read(url) {
        case .missing: return .missing
        case .unreadable: return .unreadable
        case .data(let data): return parser(data).map(Source.profiles) ?? .unreadable
        }
    }

    // MARK: - Paths and reads

    private var zenRoot: URL {
        appSupport.appendingPathComponent("zen", isDirectory: true)
    }

    private func zenProfilePath() -> String? {
        guard let data = data(zenRoot.appendingPathComponent("profiles.ini")) else { return nil }
        return ZenDiscovery.profilePath(iniText: String(decoding: data, as: UTF8.self))
    }

    private func profileDirectory(_ path: String) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : zenRoot.appendingPathComponent(path, isDirectory: true)
    }

    /// Distinguishes a missing file (no such file or directory) from one that exists but cannot be read.
    private func read(_ url: URL) -> Read {
        do {
            return .data(try Data(contentsOf: url))
        } catch {
            let nsError = error as NSError
            let isMissing = (nsError.domain == NSCocoaErrorDomain
                && (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError))
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT)
            return isMissing ? .missing : .unreadable
        }
    }

    /// The file's bytes, or nil when it is missing or unreadable.
    private func data(_ url: URL) -> Data? {
        guard case .data(let data) = read(url) else { return nil }
        return data
    }
}
