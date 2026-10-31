import Foundation
import Testing
@testable import BrowserZeroCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

private func target(_ name: String) -> Target {
    Target(browser: BrowserApp(bundleId: "com.example.\(name)", path: "/Applications/\(name).app", name: name), profile: nil)
}

@Suite struct HistoryTests {
    @Test func rankPrefersSameHost() {
        let arc = target("Arc")
        let dev = target("Dev")
        var history = History()
        for _ in 0..<3 {
            history.record(host: "jira.x", source: nil, targetId: dev.id, at: daysAgo(1))
        }
        let ranked = history.rank([arc, dev], host: "jira.x", source: nil, now: now)
        #expect(ranked.map(\.id) == [dev.id, arc.id])
    }

    @Test func rankPrefersSourceMatch() {
        let arc = target("Arc")
        let dia = target("Dia")
        var history = History()
        history.record(host: "jira.x", source: "com.a", targetId: arc.id, at: now)
        history.record(host: "jira.x", source: "com.b", targetId: dia.id, at: now)
        let ranked = history.rank([arc, dia], host: "jira.x", source: "com.b", now: now)
        #expect(ranked.map(\.id) == [dia.id, arc.id])
    }

    @Test func rankDecaysOld() {
        let old = target("Old")
        let fresh = target("Fresh")
        var history = History()
        for _ in 0..<5 {
            history.record(host: "jira.x", source: "com.a", targetId: old.id, at: daysAgo(60))
        }
        history.record(host: "jira.x", source: "com.b", targetId: fresh.id, at: now)
        let ranked = history.rank([old, fresh], host: "jira.x", source: "com.b", now: now)
        #expect(ranked.map(\.id) == [fresh.id, old.id])
    }

    @Test func rankStableWithoutHistory() {
        let targets = [target("X"), target("Y"), target("Z")]
        let ranked = History().rank(targets, host: "jira.x", source: nil, now: now)
        #expect(ranked.map(\.id) == targets.map(\.id))
    }

    @Test func suggestionAfterThree() {
        var history = History()
        for minutes in 0..<3 {
            history.record(host: "jira.x", source: nil, targetId: "dev", at: now.addingTimeInterval(Double(minutes) * 60))
        }
        #expect(history.suggestion(host: "jira.x", rules: [], dismissed: []) == "dev")
    }

    @Test func suggestionIgnoresOtherHosts() {
        var history = History()
        history.record(host: "jira.x", source: nil, targetId: "dev", at: daysAgo(3))
        history.record(host: "other.y", source: nil, targetId: "arc", at: daysAgo(2))
        history.record(host: "jira.x", source: nil, targetId: "dev", at: daysAgo(1))
        history.record(host: "jira.x", source: nil, targetId: "dev", at: now)
        #expect(history.suggestion(host: "jira.x", rules: [], dismissed: []) == "dev")
    }

    @Test func noSuggestionIfMixed() {
        var history = History()
        history.record(host: "jira.x", source: nil, targetId: "dev", at: daysAgo(2))
        history.record(host: "jira.x", source: nil, targetId: "arc", at: daysAgo(1))
        history.record(host: "jira.x", source: nil, targetId: "dev", at: now)
        #expect(history.suggestion(host: "jira.x", rules: [], dismissed: []) == nil)
    }

    @Test func noSuggestionIfRuleExists() {
        var history = History()
        for _ in 0..<3 {
            history.record(host: "jira.x", source: nil, targetId: "dev", at: now)
        }
        let glob = Rule(name: "jira", pattern: "*.x", isRegex: false, sourceApps: [], targetId: "dev")
        #expect(history.suggestion(host: "jira.x", rules: [glob], dismissed: []) == nil)

        let regex = Rule(name: "jira", pattern: "jira", isRegex: true, sourceApps: [], targetId: "dev")
        #expect(history.suggestion(host: "jira.x", rules: [regex], dismissed: []) == "dev")
    }

    @Test func noSuggestionIfDismissed() {
        var history = History()
        for _ in 0..<3 {
            history.record(host: "jira.x", source: nil, targetId: "dev", at: now)
        }
        #expect(history.suggestion(host: "jira.x", rules: [], dismissed: ["jira.x"]) == nil)
    }

    @Test func recordCapsAt2000() {
        var history = History()
        history.record(host: "jira.x", source: nil, targetId: "dev", at: now)
        for seconds in 1...2000 {
            history.record(host: "jira.x", source: nil, targetId: "dev", at: now.addingTimeInterval(-Double(seconds)))
        }
        #expect(history.choices.count == 2000)
        #expect(history.choices.contains { $0.date == now })
        #expect(!history.choices.contains { $0.date == now.addingTimeInterval(-2000) })
    }
}
