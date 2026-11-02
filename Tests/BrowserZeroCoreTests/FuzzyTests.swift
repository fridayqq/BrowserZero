import Testing
@testable import BrowserZeroCore

@Suite struct FuzzyTests {
    @Test func matchesAcrossWordStart() {
        #expect(Fuzzy.score(query: "de", candidate: "Arc · Dev") != nil)
    }

    @Test func rejectsNonSubsequence() {
        #expect(Fuzzy.score(query: "xz", candidate: "Arc · Dev") == nil)
    }

    @Test func prefersWordStartAndPrefixMatches() {
        let dev = Fuzzy.score(query: "dev", candidate: "Dia · Dev") ?? -1
        let scattered = Fuzzy.score(query: "dev", candidate: "Data Entry View") ?? -1
        #expect(dev > scattered)
    }

    @Test func matchIsCaseInsensitive() {
        #expect(Fuzzy.score(query: "zen", candidate: "Zen · Personal") != nil)
        #expect(Fuzzy.score(query: "ZEN", candidate: "zen · personal") == Fuzzy.score(query: "zen", candidate: "Zen · Personal"))
    }

    @Test func matchIsDiacriticInsensitive() {
        #expect(Fuzzy.score(query: "cafe", candidate: "Café Work") != nil)
    }

    @Test func emptyQueryScoresZero() {
        #expect(Fuzzy.score(query: "", candidate: "Arc · Dev") == 0)
        #expect(Fuzzy.score(query: "", candidate: "") == 0)
    }
}
