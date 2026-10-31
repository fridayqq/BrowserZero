import Foundation

public enum ZenDiscovery {
    public static let bundleId = "app.zen-browser.zen"
    public static let addonName = "Open external links in a container"

    /// Built-in Firefox containers, used when a container carries no name of its own.
    private static let builtInNames: [Int: String] = [1: "Personal", 2: "Work", 3: "Banking", 4: "Shopping"]
    private static let l10nNames: [String: String] = [
        "user-context-personal": "Personal",
        "user-context-work": "Work",
        "user-context-banking": "Banking",
        "user-context-shopping": "Shopping",
    ]

    /// Relative (or absolute) profile path from `profiles.ini`: the `[Install…]` section's `Default`,
    /// otherwise the `Path` of the section marked `Default=1`.
    public static func profilePath(iniText: String) -> String? {
        var sections: [(name: String, values: [String: String])] = []
        for raw in iniText.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1].values[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        return sections.first { $0.name.hasPrefix("Install") }?.values["Default"]
            ?? sections.first { $0.values["Default"] == "1" }?.values["Path"]
    }

    /// Workspaces from the plain (already decoded) `zen-sessions` JSON. Each workspace's value is
    /// the name of its default container, or "" when it has none.
    public static func workspaces(sessionsJSON: Data, containersJSON: Data?) -> [Profile]? {
        guard let json = try? JSONSerialization.jsonObject(with: sessionsJSON) as? [String: Any],
              let spaces = json["spaces"] as? [[String: Any]]
        else { return nil }

        let containers = containerNames(containersJSON)
        return spaces.compactMap { space in
            guard let name = space["name"] as? String else { return nil }
            let containerId = space["containerTabId"] as? Int ?? 0
            let icon = (space["icon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Profile(
                kind: .zenWorkspace,
                name: name,
                value: containers[containerId] ?? "",
                icon: icon
            )
        }
    }

    /// True when an active add-on whose name contains `addonName` is installed.
    public static func isAddonInstalled(extensionsJSON: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: extensionsJSON) as? [String: Any],
              let addons = json["addons"] as? [[String: Any]]
        else { return false }

        return addons.contains { addon in
            let locale = addon["defaultLocale"] as? [String: Any]
            let name = locale?["name"] as? String
            return (addon["active"] as? Bool ?? false) && (name?.contains(addonName) ?? false)
        }
    }

    /// True when `user_pref("zen.workspaces.force-container-workspace", true);` is set.
    public static func isForceContainerEnabled(prefsJS: String) -> Bool {
        let line = #"user_pref("zen.workspaces.force-container-workspace", true);"#
        return prefsJS.split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces) == line }
    }

    /// userContextId -> container name for public identities.
    private static func containerNames(_ data: Data?) -> [Int: String] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identities = json["identities"] as? [[String: Any]]
        else { return [:] }

        var result: [Int: String] = [:]
        for identity in identities where identity["public"] as? Bool ?? false {
            guard let id = identity["userContextId"] as? Int else { continue }
            let name = (identity["name"] as? String)
                ?? (identity["l10nId"] as? String).flatMap { l10n in
                    l10nNames[l10n.replacingOccurrences(of: ".label", with: "")]
                }
                ?? builtInNames[id]
            if let name { result[id] = name }
        }
        return result
    }
}
