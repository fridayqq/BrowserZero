import AppKit
import SwiftUI
import BrowserZeroCore

struct TargetsTab: View {
    @ObservedObject var state: AppState

    private static let chromeBundleId = "com.google.Chrome"

    /// One installed browser with its profile targets, in discovery order.
    private struct BrowserGroup: Identifiable {
        let plain: Target
        let profiles: [Target]
        var browser: BrowserApp { plain.browser }
        var id: String { browser.bundleId }
    }

    private var groups: [BrowserGroup] {
        state.targets.filter { $0.profile == nil }.map { plain in
            BrowserGroup(
                plain: plain,
                profiles: state.targets.filter { $0.browser.bundleId == plain.browser.bundleId && $0.profile != nil }
            )
        }
    }

    private var zenTargets: [Target] {
        state.targets.filter { $0.browser.bundleId == ZenDiscovery.bundleId && $0.profile != nil }
    }

    private var zenInstalled: Bool {
        state.targets.contains { $0.browser.bundleId == ZenDiscovery.bundleId }
    }

    private var chromeNeedsAccess: Bool {
        state.targets.contains { $0.browser.bundleId == Self.chromeBundleId && $0.profile == nil }
            && !state.targets.contains { $0.browser.bundleId == Self.chromeBundleId && $0.profile != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Browsers and the profiles, spaces and workspaces found on this Mac.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { state.refreshTargets() }
            }
            List {
                if zenInstalled {
                    zenChecklist
                }
                if chromeNeedsAccess {
                    Section {
                        Text("Chrome profiles can't be read without Full Disk Access. Grant it to Browser Zero in System Settings, Privacy & Security, Full Disk Access, then Rescan.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(groups) { group in
                    Section {
                        browserRow(group.browser)
                        Group {
                            if !group.profiles.isEmpty {
                                plainRow(group.plain)
                            }
                            ForEach(group.profiles) { profileRow($0) }
                        }
                        // Hiding the whole browser hides these too.
                        .disabled(state.config.hiddenBrowsers.contains(group.browser.bundleId))
                        .opacity(state.config.hiddenBrowsers.contains(group.browser.bundleId) ? 0.45 : 1)
                    }
                }
            }
        }
        .padding()
    }

    private var zenChecklist: some View {
        Section("Zen setup") {
            checkRow(state.zenSetup.addonInstalled, "Add-on “Open external links in a container” installed")
            checkRow(state.zenSetup.forceContainerEnabled, "Pref zen.workspaces.force-container-workspace is set")
            checkRow(zenTargets.allSatisfy(\.isSelectable), "Every workspace has a container")
        }
    }

    private func checkRow(_ ok: Bool, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
        }
    }

    private func browserRow(_ browser: BrowserApp) -> some View {
        let hidden = state.config.hiddenBrowsers.contains(browser.bundleId)
        return HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: browser.path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(browser.name)
                .fontWeight(.semibold)
                .foregroundStyle(hidden ? .secondary : .primary)
            Spacer()
            visibilityButton(hidden: hidden, help: browserHelp(hidden)) {
                state.update { config in
                    if hidden {
                        config.hiddenBrowsers.remove(browser.bundleId)
                    } else {
                        config.hiddenBrowsers.insert(browser.bundleId)
                    }
                }
            }
        }
    }

    /// The browser itself, without a space or profile. Hiding it keeps the
    /// browser's spaces and profiles in the picker.
    private func plainRow(_ target: Target) -> some View {
        let hidden = state.config.hiddenTargets.contains(target.id)
        return HStack(spacing: 8) {
            Text(Self.defaultIcon(nil))
            Text("\(target.browser.name) itself")
                .foregroundStyle(hidden ? .secondary : .primary)
            Text("no space or profile")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            visibilityButton(hidden: hidden) {
                state.update { config in
                    if hidden {
                        config.hiddenTargets.remove(target.id)
                    } else {
                        config.hiddenTargets.insert(target.id)
                    }
                }
            }
        }
        .padding(.leading, 28)
    }

    private func profileRow(_ target: Target) -> some View {
        let profile = target.profile
        let selectable = target.isSelectable
        let hidden = state.config.hiddenTargets.contains(target.id)
        return HStack(spacing: 8) {
            Text(profile?.icon ?? Self.defaultIcon(profile?.kind))
            Text(profile?.name ?? "")
                .foregroundStyle(hidden || !selectable ? .secondary : .primary)
            Text(Self.kindLabel(profile?.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !selectable {
                Text("needs container")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
            visibilityButton(hidden: hidden, disabled: !selectable) {
                state.update { config in
                    if hidden {
                        config.hiddenTargets.remove(target.id)
                    } else {
                        config.hiddenTargets.insert(target.id)
                    }
                }
            }
        }
        .padding(.leading, 28)
    }

    private func visibilityButton(hidden: Bool, disabled: Bool = false, help: String? = nil,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .frame(width: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help ?? (hidden ? "Hidden from the picker. Click to show." : "Shown in the picker. Click to hide."))
    }

    private func browserHelp(_ hidden: Bool) -> String {
        hidden ? "The browser and all its spaces and profiles are hidden. Click to show."
            : "Hide the browser together with all its spaces and profiles."
    }

    private static func kindLabel(_ kind: ProfileKind?) -> String {
        switch kind {
        case .arcSpace: "Arc space"
        case .zenWorkspace: "Zen workspace"
        case .chromiumProfile: "Chromium profile"
        case nil: "Browser"
        }
    }

    private static func defaultIcon(_ kind: ProfileKind?) -> String {
        switch kind {
        case .arcSpace: "🌀"
        case .zenWorkspace: "🧭"
        case .chromiumProfile: "👤"
        case nil: "🌐"
        }
    }
}
