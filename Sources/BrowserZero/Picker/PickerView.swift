import AppKit
import SwiftUI
import BrowserZeroCore

/// Picker content: the link's host and path, an optional learning banner, the search field and ranked rows.
struct PickerView: View {
    @ObservedObject var model: PickerModel
    /// Reports the content's height whenever it changes, so the panel can refit.
    var onHeightChange: (CGFloat) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let suggestion = model.suggestion {
                banner(for: suggestion)
            }
            search
            list
        }
        .padding(12)
        .frame(width: PickerPanel.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background { shortcuts }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { onHeightChange($0) }
        .onAppear { searchFocused = true }
    }

    /// Keeps the whole picker within `PickerPanel.maxHeight`: the list gives way to the banner when it shows.
    private var maxListHeight: CGFloat {
        model.suggestion == nil ? 290 : 255
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.host)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(model.pathText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.copyURL() }
        .help("Click or press ⌘C to copy the URL")
    }

    private func banner(for target: Target) -> some View {
        HStack(spacing: 6) {
            Text("Always open \(model.host) in \(target.displayName)?")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button("Always (⌘S)") { model.acceptSuggestion() }
                .keyboardShortcut("s", modifiers: .command)
            Button {
                model.dismissSuggestion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss suggestion")
        }
        .font(.caption)
    }

    private var search: some View {
        TextField("Filter browsers and profiles", text: $model.query)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onKeyPress(.upArrow) {
                model.move(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.move(1)
                return .handled
            }
            .onKeyPress(.return) {
                model.openSelected()
                return .handled
            }
            .onKeyPress(.escape) {
                model.close()
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
                // Bare digits open a row only while nothing is typed; otherwise they go into the field.
                guard model.query.isEmpty, press.modifiers.isEmpty, let number = Int(press.characters) else {
                    return .ignored
                }
                model.open(number - 1)
                return .handled
            }
    }

    private var list: some View {
        let rows = model.rows
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    if rows.isEmpty {
                        Text("No matching browsers or profiles")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, target in
                        row(for: target, index: index)
                            .id(target.id)
                    }
                }
            }
            .frame(maxHeight: maxListHeight)
            .onChange(of: model.selection) { _, newValue in
                guard rows.indices.contains(newValue) else { return }
                proxy.scrollTo(rows[newValue].id)
            }
        }
    }

    private func row(for target: Target, index: Int) -> some View {
        HStack(spacing: 8) {
            icon(for: target)
            Text(target.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            index == model.selection ? Color.accentColor.opacity(0.25) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.open(index) }
    }

    /// The browser icon; profiles show it small with their emoji (Zen workspaces) beside it.
    @ViewBuilder
    private func icon(for target: Target) -> some View {
        let browserIcon = Image(nsImage: NSWorkspace.shared.icon(forFile: target.browser.path))
            .resizable()
        if let profile = target.profile {
            HStack(spacing: 3) {
                browserIcon.frame(width: 14, height: 14)
                if let emoji = profile.icon, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 14))
                }
            }
            .frame(width: 36, alignment: .leading)
        } else {
            browserIcon
                .frame(width: 20, height: 20)
                .frame(width: 36, alignment: .leading)
        }
    }

    /// Invisible buttons that carry the ⌘1–9 and ⌘C shortcuts.
    private var shortcuts: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Button("") { model.open(index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("") { model.copyURL() }
                .keyboardShortcut("c", modifiers: .command)
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
