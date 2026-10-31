import Foundation

/// User settings persisted as `config.json`. Missing keys decode to their defaults.
public struct Config: Codable, Equatable, Sendable {
    public var rules: [Rule]
    public var hiddenTargets: Set<String>
    public var hiddenBrowsers: Set<String>
    public var cleanLinks: Bool
    public var dismissedSuggestions: Set<String>

    public init(
        rules: [Rule] = [],
        hiddenTargets: Set<String> = [],
        hiddenBrowsers: Set<String> = [],
        cleanLinks: Bool = true,
        dismissedSuggestions: Set<String> = []
    ) {
        self.rules = rules
        self.hiddenTargets = hiddenTargets
        self.hiddenBrowsers = hiddenBrowsers
        self.cleanLinks = cleanLinks
        self.dismissedSuggestions = dismissedSuggestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        hiddenTargets = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenTargets) ?? []
        hiddenBrowsers = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenBrowsers) ?? []
        cleanLinks = try container.decodeIfPresent(Bool.self, forKey: .cleanLinks) ?? true
        dismissedSuggestions = try container.decodeIfPresent(Set<String>.self, forKey: .dismissedSuggestions) ?? []
    }
}

/// JSON files in one directory: `config.json`, `history.json` and `targets-cache.json`.
/// Reads return defaults for missing or corrupt files. Writes are atomic and never throw;
/// a failed write leaves the previous file in place.
public final class Store: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func loadConfig() -> Config {
        load(Config.self, file: "config.json") ?? Config()
    }

    public func save(_ config: Config) {
        write(config, file: "config.json")
    }

    public func loadHistory() -> History {
        load(History.self, file: "history.json") ?? History()
    }

    public func save(_ history: History) {
        write(history, file: "history.json")
    }

    public func loadTargets() -> [Target] {
        load([Target].self, file: "targets-cache.json") ?? []
    }

    public func saveTargets(_ targets: [Target]) {
        write(targets, file: "targets-cache.json")
    }

    private func load<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, file: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(file), options: .atomic)
    }
}
