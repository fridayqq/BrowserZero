import Foundation

public enum ArcDiscovery {
    public static let bundleId = "company.thebrowser.Browser"

    /// Spaces from `Arc/StorableSidebar.json`, deduplicated by title, in sidebar order.
    /// Returns nil when the JSON does not have the expected shape.
    public static func spaces(sidebarJSON: Data) -> [Profile]? {
        guard let json = try? JSONSerialization.jsonObject(with: sidebarJSON) as? [String: Any],
              let sidebar = json["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any]
        else { return nil }

        var seen = Set<String>()
        var result: [Profile] = []
        for case let container as [String: Any] in containers {
            guard let spaces = container["spaces"] as? [Any] else { continue }
            for case let space as [String: Any] in spaces {
                guard let title = space["title"] as? String, !title.isEmpty,
                      seen.insert(title).inserted
                else { continue }
                result.append(Profile(kind: .arcSpace, name: title, value: title, icon: nil))
            }
        }
        return result
    }
}
