import Foundation

/// One recorded user choice: which target a link from `host` (via `source`) was opened in.
public struct Choice: Codable, Hashable, Sendable {
    public var host: String
    public var source: String?
    public var targetId: String
    public var date: Date

    public init(host: String, source: String?, targetId: String, date: Date) {
        self.host = host
        self.source = source
        self.targetId = targetId
        self.date = date
    }
}

/// Learned preferences from past choices, used to preselect targets and suggest rules.
public struct History: Codable, Sendable {
    /// Maximum number of choices kept; the oldest are dropped first.
    static let capacity = 2000
    /// Choices lose half their weight every `halfLifeDays`.
    static let halfLifeDays = 14.0

    public var choices: [Choice]

    public init(choices: [Choice] = []) {
        self.choices = choices
    }

    public mutating func record(host: String, source: String?, targetId: String, at date: Date) {
        choices.append(Choice(host: host, source: source, targetId: targetId, date: date))
        let excess = choices.count - Self.capacity
        guard excess > 0 else { return }
        let oldest = Set(choices.indices.sorted { (choices[$0].date, $0) < (choices[$1].date, $1) }.prefix(excess))
        choices = choices.indices.filter { !oldest.contains($0) }.map { choices[$0] }
    }

    /// Orders targets by decayed choice weight for `host` and `source`, most relevant first.
    /// Ties keep the input order.
    public func rank(_ targets: [Target], host: String, source: String?, now: Date) -> [Target] {
        let scores = targets.map { score(targetId: $0.id, host: host, source: source, now: now) }
        return targets.indices.sorted { a, b in
            scores[a] != scores[b] ? scores[a] > scores[b] : a < b
        }.map { targets[$0] }
    }

    /// Returns the target the last three choices for `host` all used, unless the host is dismissed
    /// or a non-regex rule already routes that host.
    public func suggestion(host: String, rules: [Rule], dismissed: Set<String>) -> String? {
        guard !dismissed.contains(host) else { return nil }
        let recent = choices.enumerated()
            .filter { $0.element.host == host }
            .sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }
            .prefix(3)
            .map { $0.element }
        guard recent.count == 3, let targetId = recent.first?.targetId,
              recent.allSatisfy({ $0.targetId == targetId }) else { return nil }
        let routedByRule = rules.contains { !$0.isRegex && RuleMatcher.hostMatches(glob: $0.pattern, host: host) }
        return routedByRule ? nil : targetId
    }

    private func score(targetId: String, host: String, source: String?, now: Date) -> Double {
        choices.reduce(0) { total, choice in
            guard choice.targetId == targetId else { return total }
            let weight: Double
            if choice.host == host {
                weight = choice.source == source ? 4 : 3
            } else {
                weight = 1
            }
            let ageDays = now.timeIntervalSince(choice.date) / 86_400
            return total + weight * pow(0.5, ageDays / Self.halfLifeDays)
        }
    }
}
