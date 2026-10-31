import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BrowserZeroCore

/// Rule list (first match wins, drag to reorder) with an editor sheet for each rule.
struct RulesTab: View {
    @ObservedObject var state: AppState
    /// The rule being edited. A rule whose id is not saved yet is a new one.
    @State private var editing: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Links matching a rule open in its target without asking. The first match wins.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Rule") {
                    editing = Rule(name: "", pattern: "", isRegex: false, sourceApps: [], targetId: "")
                }
            }
            List {
                ForEach(state.config.rules) { rule in
                    ruleRow(rule)
                }
                .onMove { from, to in
                    state.update { $0.rules.move(fromOffsets: from, toOffset: to) }
                }
            }
        }
        .padding()
        .sheet(item: $editing) { rule in
            RuleEditor(state: state, original: rule)
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 8) {
            Button {
                editing = rule
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RuleText.title(rule))
                        .fontWeight(.semibold)
                    Text(RuleText.condition(rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(state.targets.first { $0.id == rule.targetId }?.displayName ?? "Missing target")
                .foregroundStyle(state.targets.contains { $0.id == rule.targetId } ? Color.primary : Color.orange)
                .lineLimit(1)
            Button {
                state.update { $0.rules.removeAll { $0.id == rule.id } }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
    }
}

/// Text shared by the rule list, the editor and the test field.
enum RuleText {
    static func title(_ rule: Rule) -> String {
        if !rule.name.isEmpty { return rule.name }
        if !rule.pattern.isEmpty { return rule.pattern }
        return "Untitled rule"
    }

    /// The URL and source-app conditions in words, e.g. "*.github.com · from Telegram".
    static func condition(_ rule: Rule) -> String {
        var parts: [String] = []
        if !rule.pattern.isEmpty {
            parts.append(rule.isRegex ? "regex \(rule.pattern)" : rule.pattern)
        }
        if !rule.sourceApps.isEmpty {
            parts.append("from " + rule.sourceApps.map(SourceAppName.name(for:)).joined(separator: ", "))
        }
        return parts.isEmpty ? "Never matches" : parts.joined(separator: " · ")
    }
}

/// Display name of an app from its bundle id, falling back to the id when the app is not installed.
enum SourceAppName {
    static func name(for bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// Add or edit one rule. Save is disabled until the rule has a target, a valid regex and a condition.
private struct RuleEditor: View {
    @ObservedObject var state: AppState
    let original: Rule
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var pattern: String
    @State private var isRegex: Bool
    @State private var sourceApps: [String]
    @State private var targetId: String
    /// Display names of source apps picked in this session, keyed by bundle id.
    @State private var pickedNames: [String: String] = [:]
    @State private var pickingApp = false
    @State private var testURL = ""
    @State private var testSource = ""

    init(state: AppState, original: Rule) {
        self.state = state
        self.original = original
        _name = State(initialValue: original.name)
        _pattern = State(initialValue: original.pattern)
        _isRegex = State(initialValue: original.isRegex)
        _sourceApps = State(initialValue: original.sourceApps)
        _targetId = State(initialValue: original.targetId)
    }

    private var isExisting: Bool {
        state.config.rules.contains { $0.id == original.id }
    }

    private var draft: Rule {
        Rule(
            id: original.id,
            name: name.trimmingCharacters(in: .whitespaces),
            pattern: pattern.trimmingCharacters(in: .whitespaces),
            isRegex: isRegex,
            sourceApps: sourceApps,
            targetId: targetId
        )
    }

    private var regexValid: Bool {
        !isRegex || (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)) != nil
    }

    private var hasCondition: Bool {
        !draft.pattern.isEmpty || !sourceApps.isEmpty
    }

    private var canSave: Bool {
        !targetId.isEmpty && regexValid && hasCondition
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Match") {
                    TextField("Name", text: $name)
                    TextField(isRegex ? "Regex matched against the URL" : "Host (e.g. *.github.com)", text: $pattern)
                    Toggle("Regex", isOn: $isRegex)
                    if !regexValid {
                        Text("This regular expression doesn't compile.")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if !hasCondition {
                        Text("Add a pattern or a source app, or the rule never matches.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("Source apps") {
                    if sourceApps.isEmpty {
                        Text("Any app").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
                            ForEach(sourceApps, id: \.self) { bundleId in
                                chip(for: bundleId)
                            }
                        }
                    }
                    Button("Add App…") { pickingApp = true }
                }

                Section("Target") {
                    Picker("Open in", selection: $targetId) {
                        Text("Choose a target").tag("")
                        ForEach(state.targets.filter(\.isSelectable)) { target in
                            Text(target.displayName).tag(target.id)
                        }
                    }
                }

                Section("Test") {
                    TextField("Paste a URL", text: $testURL)
                    TextField("Source app bundle id (optional)", text: $testSource)
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                if isExisting {
                    Button("Delete", role: .destructive) {
                        state.update { $0.rules.removeAll { $0.id == original.id } }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 520, height: 620)
        .fileImporter(isPresented: $pickingApp, allowedContentTypes: [.application]) { result in
            guard case .success(let url) = result,
                  let bundleId = Bundle(url: url)?.bundleIdentifier
            else { return }
            if !sourceApps.contains(bundleId) {
                sourceApps.append(bundleId)
            }
            pickedNames[bundleId] = FileManager.default.displayName(atPath: url.path)
        }
    }

    private func chip(for bundleId: String) -> some View {
        HStack(spacing: 4) {
            Text(pickedNames[bundleId] ?? SourceAppName.name(for: bundleId))
                .lineLimit(1)
            Button {
                sourceApps.removeAll { $0 == bundleId }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Remove \(bundleId)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    /// Runs the test URL through the same cleaning and matching as the router, with this rule as it would be saved.
    private var testResult: String {
        let text = testURL.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "Paste a URL to see which rule would handle it." }
        guard let url = URL(string: text) else { return "Not a valid URL." }

        let link = state.config.cleanLinks ? LinkCleaner.clean(url) : url
        let source = testSource.trimmingCharacters(in: .whitespaces)
        var rules = state.config.rules
        if let index = rules.firstIndex(where: { $0.id == original.id }) {
            rules[index] = draft
        } else {
            rules.append(draft)
        }

        let cleaned = "Cleaned: \(link.absoluteString)"
        guard let rule = RuleMatcher.firstMatch(url: link, sourceApp: source.isEmpty ? nil : source, rules: rules) else {
            return "\(cleaned)\nNo rule matches. The picker opens."
        }
        guard let target = state.targets.first(where: { $0.id == rule.targetId }) else {
            return "\(cleaned)\nRule “\(RuleText.title(rule))” matches, but its target is missing. The picker opens."
        }
        return "\(cleaned)\nRule “\(RuleText.title(rule))” opens it in \(target.displayName)."
    }

    private func save() {
        let rule = draft
        state.update { config in
            if let index = config.rules.firstIndex(where: { $0.id == rule.id }) {
                config.rules[index] = rule
            } else {
                config.rules.append(rule)
            }
        }
        dismiss()
    }
}
