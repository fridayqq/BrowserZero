import Foundation

public enum Fuzzy {
    /// Case- and diacritic-insensitive subsequence match.
    /// Returns `nil` when `query` is not a subsequence of `candidate`; an empty query scores 0.
    /// Scoring: +10 per matched char at a word start, +5 per char consecutive with the previous match,
    /// +20 when the query is a prefix of any word.
    public static func score(query: String, candidate: String) -> Int? {
        let query = fold(query)
        if query.isEmpty { return 0 }
        let candidate = fold(candidate)
        let queryChars = Array(query)
        let candidateChars = Array(candidate)

        var score = 0
        var matched = 0
        var previousMatch: Int?
        for index in candidateChars.indices where matched < queryChars.count {
            guard candidateChars[index] == queryChars[matched] else { continue }
            if index == 0 || isSeparator(candidateChars[index - 1]) {
                score += 10
            }
            if let previousMatch, previousMatch == index - 1 {
                score += 5
            }
            previousMatch = index
            matched += 1
        }
        guard matched == queryChars.count else { return nil }

        if candidate.split(whereSeparator: isSeparator).contains(where: { $0.hasPrefix(query) }) {
            score += 20
        }
        return score
    }

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "·" || character == "-"
    }
}
