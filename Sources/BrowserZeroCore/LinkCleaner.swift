import Foundation

/// Removes redirect wrappers (Outlook, Teams, Google, Slack, Facebook, VK) and tracking
/// parameters from a link before it is opened.
public enum LinkCleaner {
    private static let maxUnwrapRounds = 5

    private static let trackingParamNames: Set<String> = [
        "fbclid", "gclid", "yclid", "mc_eid", "mc_cid", "_hsenc", "_hsmi",
    ]

    public static func clean(_ url: URL) -> URL {
        var current = url
        for _ in 0..<maxUnwrapRounds {
            guard let next = unwrapOnce(current), next != current else { break }
            current = next
        }
        return stripTrackingParams(current)
    }

    /// The target of one redirect wrapper, or nil when `url` is not a wrapper or its target is missing or invalid.
    private static func unwrapOnce(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let param: String

        if host.hasSuffix(".safelinks.protection.outlook.com") {
            param = "url"
        } else if host == "statics.teams.cdn.office.net", path.contains("/safelinks/") {
            param = "url"
        } else if isGoogleHost(host) {
            param = path == "/url" ? "q" : "url"
        } else if host == "slack-redir.net", path == "/link" {
            param = "url"
        } else if host == "l.facebook.com" || host == "lm.facebook.com", path == "/l.php" {
            param = "u"
        } else if host == "away.vk.com", path == "/away.php" {
            param = "to"
        } else {
            return nil
        }

        return targetURL(in: url, param: param)
    }

    /// Matches `google.<tld>` and `www.google.<tld>`.
    private static func isGoogleHost(_ host: String) -> Bool {
        var labels = host.split(separator: ".").map(String.init)
        if labels.first == "www" {
            labels.removeFirst()
        }
        return labels.count >= 2 && labels[0] == "google"
    }

    /// The query parameter `param` parsed as an absolute http(s) URL with a host.
    private static func targetURL(in url: URL, param: String) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == param })?.value,
              let target = URL(string: value),
              let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = target.host, !host.isEmpty
        else { return nil }
        return target
    }

    /// Drops tracking parameters, keeping the remaining ones in their original order and encoding.
    private static func stripTrackingParams(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems
        else { return url }

        let kept = items.filter { !isTrackingParam($0.name.removingPercentEncoding ?? $0.name) }
        guard kept.count != items.count else { return url }

        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    private static func isTrackingParam(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.hasPrefix("utm_") || trackingParamNames.contains(lowercased)
    }
}
