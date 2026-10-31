import AppKit
import SwiftUI
import BrowserZeroCore

/// The picker: a non-activating panel at the mouse cursor that asks where a link should open.
/// One instance serves every link at a time; showing it again replaces its content and position.
final class PickerPanel: NSPanel, NSWindowDelegate {
    static let width: CGFloat = 300
    static let maxHeight: CGFloat = 420

    /// Called after the panel closes for any reason, so that queued links can be shown.
    var onClose: (() -> Void)?

    /// Close-on-resign-key only arms once the panel has really become key. Activating an accessory app
    /// is asynchronous, so an early resign-key must not close the panel before the user sees it.
    private var isArmed = false
    /// Incremented on every show, so a retry timer from an earlier show does nothing.
    private var showToken = 0
    /// The model of the content currently shown, so that key-window changes can re-focus its search field.
    private weak var currentModel: PickerModel?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    /// Shows the picker for `url` at the cursor, replacing whatever it showed before.
    func show(url: URL, source: String?, state: AppState) {
        showToken += 1
        let token = showToken
        isArmed = false

        let model = PickerModel(url: url, source: source, state: state, close: { [weak self] in
            self?.close()
        })
        currentModel = model
        let hosting = NSHostingView(rootView: PickerView(model: model, onHeightChange: { [weak self] height in
            DispatchQueue.main.async { self?.refit(height: height) }
        }))
        contentView = hosting

        let height = min(max(hosting.fittingSize.height, 1), Self.maxHeight)
        let size = NSSize(width: Self.width, height: height)
        setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        present()

        // If the first activation did not make the panel key, try once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self, token == self.showToken, self.isVisible, !self.isKeyWindow else { return }
            self.present()
        }
    }

    override func close() {
        let wasVisible = isVisible
        super.close()
        if wasVisible {
            onClose?()
        }
    }

    /// Esc reaches here even when no field has focus.
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        isArmed = true
        currentModel?.requestSearchFocus()
    }

    func windowDidResignKey(_ notification: Notification) {
        NSLog("Browser Zero: picker resign key, armed=\(isArmed)")
        guard isArmed else { return }
        isArmed = false
        close()
    }

    private func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Resizes to the content's height while keeping the top edge fixed; the bottom stays on screen.
    private func refit(height: CGFloat) {
        guard isVisible else { return }
        let newHeight = min(max(height, 1), Self.maxHeight)
        guard abs(newHeight - frame.height) > 0.5 else { return }
        let lowestY = (screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        let y = max(frame.maxY - newHeight, lowestY + 20)
        setFrame(NSRect(x: frame.minX, y: y, width: frame.width, height: frame.maxY - y), display: true)
    }

    /// Top edge just above the cursor, horizontally centred on it, kept 20pt inside the screen with the cursor.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(origin: .zero, size: size)
        return NSPoint(
            x: clamp(mouse.x - size.width / 2, min: screen.minX + 20, max: screen.maxX - size.width - 20),
            y: clamp(mouse.y - (size.height - 30), min: screen.minY + 20, max: screen.maxY - size.height - 20)
        )
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}
