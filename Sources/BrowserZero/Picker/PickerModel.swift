import AppKit
import Foundation
import BrowserZeroCore

/// What the picker panel shows and does for one incoming link: ranked targets, the fuzzy query,
/// the keyboard selection and the learned rule suggestion.
@MainActor
final class PickerModel: ObservableObject {
    let url: URL
    let source: String?

    @Published var query = "" {
        didSet {
            if query != oldValue { selection = 0 }
        }
    }
    @Published var selection = 0
    /// Bumped whenever the panel becomes key again, so the view can re-take focus for the search field.
    @Published private(set) var focusTick = 0

    /// Target the learning banner offers to make permanent for this host, if any.
    private(set) var suggestion: Target?

    private let state: AppState
    private let closePanel: () -> Void
    /// Visible targets in history rank order, before any query filtering.
    private let ranked: [Target]

    init(url: URL, source: String?, state: AppState, close: @escaping () -> Void) {
        self.url = url
        self.source = source
        self.state = state
        self.closePanel = close

        let visible = state.visibleTargets()
        let host = url.host ?? ""
        ranked = state.history.rank(visible, host: host, source: source, now: Date())
        if let targetId = state.history.suggestion(
            host: host,
            rules: state.config.rules,
            dismissed: state.config.dismissedSuggestions
        ) {
            suggestion = visible.first { $0.id == targetId }
        }
    }

    var host: String {
        url.host ?? ""
    }

    /// Path and query of the link, for the header.
    var pathText: String {
        url.path + (url.query.map { "?" + $0 } ?? "")
    }

    /// Ranked targets, filtered and sorted by fuzzy score against the query when one is typed.
    /// Equal scores keep their rank order.
    var rows: [Target] {
        guard !query.isEmpty else { return ranked }
        let matches = ranked.enumerated().compactMap { index, target -> (index: Int, score: Int, target: Target)? in
            guard let score = Fuzzy.score(query: query, candidate: target.displayName) else { return nil }
            return (index, score, target)
        }
        return matches.sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }.map(\.target)
    }

    /// Moves the selection by `delta`, clamped to the visible rows.
    func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else {
            selection = 0
            return
        }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func openSelected() {
        open(selection)
    }

    /// Opens the link in the row at `index`, records the choice and closes the panel.
    func open(_ index: Int) {
        let candidates = rows
        guard candidates.indices.contains(index) else { return }
        complete(candidates[index])
    }

    /// Creates a host rule for the suggested target, then opens the link there.
    func acceptSuggestion() {
        guard let target = suggestion else { return }
        state.config.rules.append(Rule(
            id: UUID(),
            name: host,
            pattern: host,
            isRegex: false,
            sourceApps: [],
            targetId: target.id
        ))
        state.saveConfig()
        complete(target)
    }

    /// Hides the banner for this host for good.
    func dismissSuggestion() {
        state.config.dismissedSuggestions.insert(host)
        state.saveConfig()
        suggestion = nil
    }

    func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func close() {
        closePanel()
    }

    func requestSearchFocus() {
        focusTick += 1
    }

    private func complete(_ target: Target) {
        Opener.open([url], target: target, zenSetup: state.zenSetup)
        state.record(host: host, source: source, targetId: target.id)
        closePanel()
    }
}
