import AppKit
import SwiftUI
import BrowserZeroCore

/// The picker: a non-activating panel at the mouse cursor that asks where a link should open.
/// One instance serves every link; showing it again replaces its content and position.
final class PickerPanel: NSPanel, NSWindowDelegate {
    static let width: CGFloat = 300
    static let maxHeight: CGFloat = 420

    /// The panel closes on resign-key only once it has really become key. Activation of an
    /// accessory app is asynchronous, so the first resign-key would otherwise close it at once.
    private var isArmed = false

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

    /// Shows the picker for `url`, replacing whatever it showed before.
    func show(url: URL, source: String?, state: AppState) {
        let model = PickerModel(url: url, source: source, state: state, close: { [weak self] in
            self?.close()
        })
        let hosting = NSHostingView(rootView: PickerView(model: model))
        contentView = hosting

        let height = min(max(hosting.fittingSize.height, 1), Self.maxHeight)
        setContentSize(NSSize(width: Self.width, height: height))
        setFrameOrigin(origin(for: NSSize(width: Self.width, height: height)))

        isArmed = false
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self, self.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            self.isArmed = true
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isArmed else { return }
        isArmed = false
        close()
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
