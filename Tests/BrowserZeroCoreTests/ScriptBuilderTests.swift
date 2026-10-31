import Foundation
import Testing
@testable import BrowserZeroCore

private func compiles(_ script: String) -> Bool {
    var error: NSDictionary?
    return NSAppleScript(source: script)?.compileAndReturnError(&error) ?? false
}

@Suite struct ScriptBuilderTests {
    @Test func arcScriptEscapes() throws {
        let url = try #require(URL(string: "https://e.com/?q=%22x%22%5Cy"))
        let script = ScriptBuilder.arcScript(space: #"My "Work""#, urls: [url])
        #expect(script.contains(#"tell space "My \"Work\"""#))
        #expect(script.contains(#"{URL:"https://e.com/?q=%22x%22%5Cy"}"#))
        #expect(compiles(script))
    }

    @Test func arcScriptEscapesSpaceOnly() throws {
        let url = try #require(URL(string: "https://e.com/plain"))
        let script = ScriptBuilder.arcScript(space: #"a\b"c"#, urls: [url])
        #expect(script.contains(#"tell space "a\\b\"c""#))
        #expect(compiles(script))
    }

    @Test func arcScriptShape() throws {
        let first = try #require(URL(string: "https://e.com/1"))
        let second = try #require(URL(string: "https://e.com/2"))
        let script = ScriptBuilder.arcScript(space: "Dev", urls: [first, second])
        #expect(script.contains(#"make new tab with properties {URL:"https://e.com/1"}"#))
        #expect(script.contains(#"make new tab with properties {URL:"https://e.com/2"}"#))
        #expect(script.contains("if (count of windows) is 0 then make new window"))
        #expect(script.contains("tell front window"))
        #expect(script.contains("focus"))
        #expect(script.contains("activate"))
    }

    @Test func zenURLRoundTrip() throws {
        let original = "https://e.com/a?b=1&c=2+3#frag"
        let url = try #require(URL(string: original))
        let built = ScriptBuilder.zenContainerURL(container: "Work", url: url)
        #expect(built.absoluteString.hasPrefix("ext+container:"))
        let components = try #require(URLComponents(
            string: built.absoluteString.replacingOccurrences(of: "ext+container:", with: "x:?")
        ))
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "url" }?.value == original)
        #expect(items.first { $0.name == "name" }?.value == "Work")
    }

    @Test func chromiumArgumentsPrependProfile() throws {
        let url = try #require(URL(string: "https://e.com/x"))
        #expect(ScriptBuilder.chromiumArguments(profileDir: "Profile 1", urls: [url]) == ["--profile-directory=Profile 1", "https://e.com/x"])
    }
}
