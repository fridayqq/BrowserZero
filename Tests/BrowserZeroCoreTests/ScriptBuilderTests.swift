import Foundation
import Testing
@testable import BrowserZeroCore

private func compiles(_ script: String) -> Bool {
    var error: NSDictionary?
    return NSAppleScript(source: script)?.compileAndReturnError(&error) ?? false
}

@Suite struct ScriptBuilderTests {
    @Test func arcScriptEscapes() throws {
        // Built from the raw string; URL(string:) may percent-encode it, so fall back to URLComponents if it refuses.
        let raw = #"https://e.com/?q="x"\y"#
        var components = URLComponents()
        components.scheme = "https"
        components.host = "e.com"
        components.path = "/"
        components.query = #"q="x"\y"#
        let url = try #require(URL(string: raw) ?? components.url)
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

    @Test func arcScriptHasTimeout() throws {
        let url = try #require(URL(string: "https://e.com/1"))
        let script = ScriptBuilder.arcScript(space: "Dev", urls: [url])
        #expect(script.contains("with timeout of 10 seconds"))
        #expect(script.contains("end timeout"))
        #expect(compiles(script))
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

    @Test func zenURLCyrillic() throws {
        let url = try #require(URL(string: "https://ru.wikipedia.org/wiki/Москва"))
        let built = ScriptBuilder.zenContainerURL(container: "Work", url: url)
        #expect(built.absoluteString.allSatisfy { $0.isASCII })
        let components = try #require(URLComponents(
            string: built.absoluteString.replacingOccurrences(of: "ext+container:", with: "x:?")
        ))
        #expect(components.queryItems?.first { $0.name == "url" }?.value == url.absoluteString)
    }

    @Test func chromiumArgumentsPrependProfile() throws {
        let url = try #require(URL(string: "https://e.com/x"))
        #expect(ScriptBuilder.chromiumArguments(profileDir: "Profile 1", urls: [url]) == ["--profile-directory=Profile 1", "https://e.com/x"])
    }
}
