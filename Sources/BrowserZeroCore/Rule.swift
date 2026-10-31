import Foundation

/// A user rule that routes matching links to a fixed target.
public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Host glob (`*.x.com`, `x.com`, `*`) or, when `isRegex`, a regex matched against the full URL.
    /// Empty means the URL condition always passes.
    public var pattern: String
    public var isRegex: Bool
    /// Source app bundle IDs. Empty means any source app.
    public var sourceApps: [String]
    public var targetId: String

    public init(id: UUID = UUID(), name: String, pattern: String, isRegex: Bool, sourceApps: [String], targetId: String) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isRegex = isRegex
        self.sourceApps = sourceApps
        self.targetId = targetId
    }
}

public enum RuleMatcher {
    /// Matches a host against a glob. `*` matches any host; `*.x.com` matches `x.com` and any subdomain.
    /// Comparison is case-insensitive.
    public static func hostMatches(glob: String, host: String) -> Bool {
        let glob = glob.lowercased()
        let host = host.lowercased()
        if glob == "*" { return true }
        if glob.hasPrefix("*.") {
            let base = String(glob.dropFirst(2))
            return host == base || host.hasSuffix("." + base)
        }
        return host == glob
    }

    /// True when the rule's URL condition and source-app condition both hold.
    /// A rule with no pattern and no source apps never matches.
    public static func matches(_ rule: Rule, url: URL, sourceApp: String?) -> Bool {
        if rule.pattern.isEmpty && rule.sourceApps.isEmpty { return false }
        if !rule.pattern.isEmpty {
            let urlMatches: Bool
            if rule.isRegex {
                urlMatches = regexMatches(rule.pattern, in: url.absoluteString)
            } else {
                urlMatches = hostMatches(glob: rule.pattern, host: url.host ?? "")
            }
            if !urlMatches { return false }
        }
        if !rule.sourceApps.isEmpty {
            guard let sourceApp, rule.sourceApps.contains(sourceApp) else { return false }
        }
        return true
    }

    /// Returns the first rule, in array order, that matches.
    public static func firstMatch(url: URL, sourceApp: String?, rules: [Rule]) -> Rule? {
        rules.first { matches($0, url: url, sourceApp: sourceApp) }
    }

    /// An invalid regex never matches.
    private static func regexMatches(_ pattern: String, in string: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}
