import Foundation
import BrowserZeroCore

/// Decides where an incoming link goes: a matching rule opens it directly, otherwise the picker is shown.
@MainActor
final class Router {
    private let state: AppState
    private let showPicker: @MainActor (URL, String?) -> Void

    init(state: AppState, showPicker: @escaping @MainActor (URL, String?) -> Void) {
        self.state = state
        self.showPicker = showPicker
    }

    /// `forcePicker` (Option held) skips rules. Rules only route when the target still exists.
    func handle(_ url: URL, sourceApp: String?, forcePicker: Bool) {
        let link = state.config.cleanLinks ? LinkCleaner.clean(url) : url

        if !forcePicker,
           let rule = RuleMatcher.firstMatch(url: link, sourceApp: sourceApp, rules: state.config.rules),
           let target = state.targets.first(where: { $0.id == rule.targetId }) {
            Opener.open([link], target: target, zenSetup: state.zenSetup)
            state.record(host: link.host ?? "", source: sourceApp, targetId: target.id)
            return
        }

        showPicker(link, sourceApp)
    }
}
