import Foundation

public enum ChromiumDiscovery {
    /// Bundle id -> folder (inside ~/Library/Application Support) that holds `Local State`.
    public static let dataDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "ru.yandex.desktop.yandex-browser": "Yandex/YandexBrowser",
        "ai.perplexity.comet": "Comet",
        "company.thebrowser.dia": "Dia/User Data",
    ]

    /// Profiles from a Chromium `Local State` file, in `profiles_order`. Returns [] when there is at
    /// most one profile, and nil when the JSON cannot be parsed.
    public static func profiles(localStateJSON: Data) -> [Profile]? {
        guard let json = try? JSONSerialization.jsonObject(with: localStateJSON) as? [String: Any]
        else { return nil }
        guard let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]],
              cache.count > 1
        else { return [] }

        let order = (profile["profiles_order"] as? [String]) ?? cache.keys.sorted()
        let dirs = order.filter { cache[$0] != nil } + cache.keys.filter { !order.contains($0) }.sorted()

        return dirs.map { dir in
            Profile(
                kind: .chromiumProfile,
                name: cache[dir]?["name"] as? String ?? dir,
                value: dir,
                icon: nil
            )
        }
    }
}
