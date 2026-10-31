import Foundation
import Testing
@testable import BrowserZeroCore

private func cleaned(_ string: String) -> String {
    LinkCleaner.clean(URL(string: string)!).absoluteString
}

@Suite struct LinkCleanerTests {
    @Test func unwrapsOutlookSafeLinks() {
        #expect(cleaned("https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fdev.atlassian.net%2Fbrowse%2FDATA-1&data=05")
            == "https://dev.atlassian.net/browse/DATA-1")
    }

    @Test func unwrapsTeamsSafeLinks() {
        #expect(cleaned("https://statics.teams.cdn.office.net/evergreen-assets/safelinks/1/atp-safelinks.html?url=https%3A%2F%2Fexample.com%2Fa&locale=en")
            == "https://example.com/a")
    }

    @Test func unwrapsGoogle() {
        #expect(cleaned("https://www.google.com/url?q=https://example.com/x&sa=D")
            == "https://example.com/x")
    }

    @Test func unwrapsNested() {
        #expect(cleaned("https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fwww.google.com%2Furl%3Fq%3Dhttps%253A%252F%252Fexample.com%252Finner&data=05")
            == "https://example.com/inner")
    }

    @Test func stripsTracking() {
        #expect(cleaned("https://example.com/p?utm_source=a&id=7&fbclid=z#top")
            == "https://example.com/p?id=7#top")
    }

    @Test func removesEmptyQuery() {
        #expect(cleaned("https://example.com/p?utm_medium=x") == "https://example.com/p")
    }

    @Test func preservesEncodingAndOrderOfRemainingParams() {
        #expect(cleaned("https://example.com/p?q=a%20b&utm_x=1&z=%2F&id=7")
            == "https://example.com/p?q=a%20b&z=%2F&id=7")
    }

    @Test func brokenWrapperUnchanged() {
        #expect(cleaned("https://eur02.safelinks.protection.outlook.com/?data=x")
            == "https://eur02.safelinks.protection.outlook.com/?data=x")
        #expect(cleaned("https://eur02.safelinks.protection.outlook.com/?url=not%20a%20url")
            == "https://eur02.safelinks.protection.outlook.com/?url=not%20a%20url")
    }

    @Test func plainLinkUnchanged() {
        #expect(cleaned("https://github.com/a/b?tab=readme") == "https://github.com/a/b?tab=readme")
    }
}
