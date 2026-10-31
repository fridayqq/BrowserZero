import Foundation

/// Builds the payloads used to open links in a specific profile: AppleScript for Arc,
/// `ext+container:` URLs for Zen, and command-line arguments for Chromium.
public enum ScriptBuilder {
    public static func arcScript(space: String, urls: [URL]) -> String {
        let tabs = urls
            .map { "make new tab with properties {URL:\"\(escapeAppleScript($0.absoluteString))\"}" }
            .joined(separator: "\n")
        return """
        tell application "Arc"
            if (count of windows) is 0 then make new window
            tell front window
                tell space "\(escapeAppleScript(space))"
                    focus
                    \(tabs)
                end tell
            end tell
            activate
        end tell
        """
    }

    /// `ext+container:name=<container>&url=<url>` as understood by the "Open external links in a container" add-on.
    public static func zenContainerURL(container: String, url: URL) -> URL {
        let query = "name=\(percentEncode(container))&url=\(percentEncode(url.absoluteString))"
        return URL(string: "ext+container:\(query)") ?? url
    }

    public static func chromiumArguments(profileDir: String, urls: [URL]) -> [String] {
        ["--profile-directory=\(profileDir)"] + urls.map(\.absoluteString)
    }

    private static func escapeAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
