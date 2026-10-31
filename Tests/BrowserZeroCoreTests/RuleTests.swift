import Foundation
import Testing
@testable import BrowserZeroCore

private func url(_ string: String) -> URL {
    URL(string: string)!
}

private func hostRule(_ pattern: String, sourceApps: [String] = [], target: String = "t") -> Rule {
    Rule(name: "r", pattern: pattern, isRegex: false, sourceApps: sourceApps, targetId: target)
}

@Suite struct RuleTests {
    @Test func globMatchesSubdomainAndApex() {
        #expect(RuleMatcher.hostMatches(glob: "*.atlassian.net", host: "dev.atlassian.net"))
        #expect(RuleMatcher.hostMatches(glob: "*.atlassian.net", host: "atlassian.net"))
        #expect(RuleMatcher.hostMatches(glob: "*.atlassian.net", host: "evilatlassian.net") == false)
    }

    @Test func exactHost() {
        #expect(RuleMatcher.hostMatches(glob: "example.com", host: "example.com"))
        #expect(RuleMatcher.hostMatches(glob: "example.com", host: "sub.example.com") == false)
    }

    @Test func hostComparisonIsCaseInsensitive() {
        #expect(RuleMatcher.hostMatches(glob: "*.Atlassian.NET", host: "Dev.atlassian.net"))
    }

    @Test func starMatchesAnyHost() {
        #expect(RuleMatcher.hostMatches(glob: "*", host: "anything.example"))
    }

    @Test func regexOnFullURL() {
        let rule = Rule(name: "jira", pattern: "jira.*/browse/", isRegex: true, sourceApps: [], targetId: "t")
        #expect(RuleMatcher.matches(rule, url: url("https://jira.example.com/browse/DATA-1"), sourceApp: nil))
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/docs"), sourceApp: nil) == false)
    }

    @Test func regexIsCaseInsensitive() {
        let rule = Rule(name: "jira", pattern: "JIRA.*/browse/", isRegex: true, sourceApps: [], targetId: "t")
        #expect(RuleMatcher.matches(rule, url: url("https://jira.example.com/browse/DATA-1"), sourceApp: nil))
    }

    @Test func sourceAppOnly() {
        let rule = hostRule("", sourceApps: ["com.microsoft.teams2"])
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/a"), sourceApp: "com.microsoft.teams2"))
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/a"), sourceApp: nil) == false)
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/a"), sourceApp: "com.apple.mail") == false)
    }

    @Test func bothConditions() {
        let rule = hostRule("*.atlassian.net", sourceApps: ["com.microsoft.teams2"])
        #expect(RuleMatcher.matches(rule, url: url("https://dev.atlassian.net/browse/X-1"), sourceApp: "com.microsoft.teams2"))
        #expect(RuleMatcher.matches(rule, url: url("https://dev.atlassian.net/browse/X-1"), sourceApp: "com.apple.mail") == false)
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/"), sourceApp: "com.microsoft.teams2") == false)
    }

    @Test func emptyRuleNeverMatches() {
        let rule = hostRule("", sourceApps: [])
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/"), sourceApp: "com.microsoft.teams2") == false)
        #expect(RuleMatcher.matches(rule, url: url("https://example.com/"), sourceApp: nil) == false)
    }

    @Test func invalidRegexSkipped() {
        let bad = Rule(name: "bad", pattern: "(", isRegex: true, sourceApps: [], targetId: "bad")
        #expect(RuleMatcher.matches(bad, url: url("https://example.com/"), sourceApp: nil) == false)
        let good = hostRule("example.com", target: "good")
        #expect(RuleMatcher.firstMatch(url: url("https://example.com/"), sourceApp: nil, rules: [bad, good]) == good)
    }

    @Test func firstMatchWins() {
        let first = hostRule("*.example.com", target: "first")
        let second = hostRule("example.com", target: "second")
        #expect(RuleMatcher.firstMatch(url: url("https://example.com/"), sourceApp: nil, rules: [first, second]) == first)
        #expect(RuleMatcher.firstMatch(url: url("https://example.com/"), sourceApp: nil, rules: [second, first]) == second)
        #expect(RuleMatcher.firstMatch(url: url("https://other.org/"), sourceApp: nil, rules: [first, second]) == nil)
    }

    @Test func ruleCodableRoundTrip() throws {
        let rule = hostRule("*.x.com", sourceApps: ["a"], target: "t")
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(Rule.self, from: data) == rule)
    }
}
