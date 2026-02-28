import AppKit
import ApplicationServices
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "WindowPicker")

/// Two ways to select a target window:
///   1. `pickFrontmostWindow()` – instant, no interaction.
///   2. `startClickToPickMode(completion:)` – shows a crosshair overlay; user clicks a window.
class WindowPicker {

    private let enumerator = WindowEnumerator()
    private var overlayWindow: PickerOverlayWindow?

    // MARK: - Frontmost

    /// Returns the focused (or first) window of the currently active application.
    func pickFrontmostWindow() -> WindowRef? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.warning("No frontmost application")
            return nil
        }

        // Skip ourselves
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            logger.info("Frontmost is TopPin itself – skipping")
            return nil
        }

        let windows = enumerator.windows(for: frontApp)

        // Prefer the focused window
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
           let focused = focusedValue {
            if let match = windows.first(where: { CFEqual($0.element, focused as! AXUIElement) }) {
                return match
            }
        }

        return windows.first
    }

    // MARK: - Click-to-pick

    /// Presents a full-screen crosshair overlay.  When the user clicks, the window
    /// under the cursor is resolved to a `WindowRef` and returned via `completion`.
    /// Pressing Escape cancels and calls `completion(nil)`.
    func startClickToPickMode(completion: @escaping (WindowRef?) -> Void) {
        let overlay = PickerOverlayWindow()
        self.overlayWindow = overlay

        overlay.onPick = { [weak self] screenPoint in
            self?.overlayWindow = nil
            let ref = self?.findWindow(at: screenPoint)
            completion(ref)
        }
        overlay.onCancel = { [weak self] in
            self?.overlayWindow = nil
            completion(nil)
        }

        overlay.makeKeyAndOrderFront(nil)
    }

    // MARK: - Private helpers

    /// Uses CGWindowList to find the topmost non-TopPin window at `point` (CG coordinates,
    /// origin top-left), then matches it to an AXUIElement by PID + bounds.
    private func findWindow(at point: CGPoint) -> WindowRef? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            guard
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                let ownerPID   = info[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID != myPID
            else { continue }

            let bounds = CGRect(
                x:      Double(boundsDict["X"]      ?? 0),
                y:      Double(boundsDict["Y"]      ?? 0),
                width:  Double(boundsDict["Width"]  ?? 0),
                height: Double(boundsDict["Height"] ?? 0)
            )

            guard bounds.contains(point) else { continue }

            // Match AX window by owner PID + overlapping bounds
            guard let app = NSWorkspace.shared.runningApplications
                    .first(where: { $0.processIdentifier == ownerPID })
            else { continue }

            let candidates = enumerator.windows(for: app)

            // Best match: top-left corner within 5 pt tolerance
            let dx = bounds.minX
            let dy = bounds.minY
            let bestMatch: WindowRef? = candidates.first(where: {
                abs($0.bounds.minX - dx) < 5 && abs($0.bounds.minY - dy) < 5
            }) ?? candidates.first

            if let match = bestMatch {
                logger.info("Click-to-pick resolved: \(match.appName) – \(match.title)")
                return match
            }
        }

        let desc = "\(point)"
        logger.warning("Click-to-pick: no window found at \(desc)")
        return nil
    }
}

// MARK: - Overlay window

final class PickerOverlayWindow: NSWindow {
    var onPick:   ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        // Cover all screens
        let screenRect = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        super.init(contentRect: screenRect,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        backgroundColor   = NSColor(white: 0, alpha: 0.01)   // near-transparent
        level             = .screenSaver
        isOpaque          = false
        hasShadow         = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = PickerContentView(frame: screenRect)
        content.onPick   = { [weak self] pt in self?.onPick?(pt);   self?.close() }
        content.onCancel = { [weak self] in self?.onCancel?(); self?.close() }
        contentView = content
    }

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay content view

final class PickerContentView: NSView {
    var onPick:   ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Convert AppKit coords (bottom-left origin) → CG coords (top-left origin)
        let winPoint    = event.locationInWindow
        let screenPoint = window?.convertPoint(toScreen: winPoint) ?? winPoint
        let screenH     = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })?.frame.height
                         ?? NSScreen.main?.frame.height ?? 0
        let cgPoint     = CGPoint(x: screenPoint.x, y: screenH - screenPoint.y)
        onPick?(cgPoint)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }   // Escape
    }

    // Subtle crosshair labels
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.01).setFill()
        dirtyRect.fill()

        // Central instruction text
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: {
                let s = NSShadow()
                s.shadowColor  = NSColor.black
                s.shadowOffset = NSSize(width: 1, height: -1)
                s.shadowBlurRadius = 4
                return s
            }()
        ]
        let text = "Click a window to pin it  ·  Esc to cancel" as NSString
        let size = text.size(withAttributes: attrs)
        let pt   = NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height + size.height) / 2 + 40)
        text.draw(at: pt, withAttributes: attrs)
    }
}
