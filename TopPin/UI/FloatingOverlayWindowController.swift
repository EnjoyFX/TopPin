import AppKit
import AVFoundation
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "FloatingOverlay")

// MARK: - Controller

/// Creates a borderless NSWindow at `.floating` level that:
///  • renders a live SCStream of the target window (always on top, no flash)
///  • is fully click-through (`ignoresMouseEvents = true`) so native events reach the original window
///  • activates the original app on hover and restores the previous app when the mouse leaves
///  • tracks the original window's position via AXObserver so the overlay follows it
@MainActor
final class FloatingOverlayWindowController: NSWindowController {

    private let captureSession = WindowCaptureSession()
    private var positionTracker: AXPositionTracker?
    private(set) var targetWindowRef: WindowRef

    var onWindowGone: (() -> Void)?

    // MARK: Hover-to-focus state
    private var mouseTrackTimer: Timer?
    private var isMouseOverOverlay = false
    private var previousFrontmostApp: NSRunningApplication?

    // MARK: Init

    init(windowRef: WindowRef) {
        self.targetWindowRef = windowRef

        let appKitFrame = CGRect.cgToAppKit(windowRef.bounds)

        let win = FloatingWindow(
            contentRect: appKitFrame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        win.level             = .floating   // Always above normal app windows
        win.isOpaque          = true
        win.hasShadow         = true
        win.backgroundColor   = .black
        win.isReleasedWhenClosed = false
        win.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Pass all mouse events through to the original window beneath the overlay.
        // The original window sits at the same screen coordinates and receives native
        // clicks, drags and scroll — no CGEvent forwarding needed.
        win.ignoresMouseEvents = true

        let captureView = CaptureContentView(frame: NSRect(origin: .zero, size: appKitFrame.size))
        captureView.autoresizingMask = [.width, .height]
        win.contentView = captureView

        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Start

    func startCapture() async throws {
        let view = window?.contentView as? CaptureContentView

        captureSession.onFrame = { [weak view] buffer in
            view?.displayLayer.enqueue(buffer)
        }
        captureSession.onWindowGone = { [weak self] in
            self?.onWindowGone?()
        }

        try await captureSession.start(matching: targetWindowRef)

        window?.orderFront(nil)
        logger.info("Floating overlay visible for '\(self.targetWindowRef.title)'")

        // Track position/size changes via AX notifications
        positionTracker = AXPositionTracker(windowRef: targetWindowRef) { [weak self] newBounds in
            guard let self else { return }
            self.targetWindowRef.bounds = newBounds
            let frame = CGRect.cgToAppKit(newBounds)
            self.window?.setFrame(frame, display: true, animate: false)
        }
        positionTracker?.start()
        startHoverTracking()
    }

    // MARK: - Stop

    func stopCapture() async {
        stopHoverTracking()
        positionTracker?.stop()
        positionTracker = nil
        await captureSession.stop()
        window?.close()
        logger.info("Floating overlay closed")
    }

    // MARK: - Hover-to-focus

    /// Polls the cursor position every 50 ms. When the cursor enters the overlay
    /// the original app is activated; when it leaves, the previous app is restored.
    /// The overlay remains click-through (`ignoresMouseEvents = true`) so that
    /// native clicks reach the original window directly.
    private func startHoverTracking() {
        mouseTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so MainActor isolation is guaranteed.
            MainActor.assumeIsolated { self?.updateHoverState() }
        }
    }

    private func stopHoverTracking() {
        mouseTrackTimer?.invalidate()
        mouseTrackTimer = nil
        if isMouseOverOverlay { restorePreviousApp() }
    }

    private func updateHoverState() {
        guard let frame = window?.frame else { return }
        let isOver = frame.contains(NSEvent.mouseLocation)
        guard isOver != isMouseOverOverlay else { return }
        isMouseOverOverlay = isOver
        if isOver {
            previousFrontmostApp = NSWorkspace.shared.frontmostApplication
            NSWorkspace.shared.runningApplications
                .first(where: { $0.processIdentifier == targetWindowRef.pid })?
                .activate(options: [.activateIgnoringOtherApps])
            logger.debug("Hover enter – activating '\(self.targetWindowRef.appName)'")
        } else {
            restorePreviousApp()
        }
    }

    private func restorePreviousApp() {
        guard let prev = previousFrontmostApp,
              prev.processIdentifier != targetWindowRef.pid,
              prev.bundleIdentifier  != Bundle.main.bundleIdentifier
        else { previousFrontmostApp = nil; return }
        prev.activate(options: [.activateIgnoringOtherApps])
        logger.debug("Hover exit – restoring '\(prev.localizedName ?? "?")'")
        previousFrontmostApp = nil
    }
}

// MARK: - FloatingWindow

/// Borderless floating window. Never becomes key or main since it is click-through.
private final class FloatingWindow: NSWindow {
    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - CaptureContentView

/// Displays `AVSampleBufferDisplayLayer` frames and forwards
/// mouse/scroll events to the original window's process.
final class CaptureContentView: NSView {

    let displayLayer: AVSampleBufferDisplayLayer

    override init(frame: NSRect) {
        displayLayer = AVSampleBufferDisplayLayer()

        super.init(frame: frame)

        wantsLayer = true
        displayLayer.frame              = bounds
        displayLayer.autoresizingMask   = [.layerWidthSizable, .layerHeightSizable]
        displayLayer.videoGravity       = .resizeAspectFill
        displayLayer.backgroundColor    = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - AXPositionTracker

/// Listens for kAXWindowMoved / kAXWindowResized on the target AXUIElement
/// and calls `onMove` with the updated CGRect (CG coordinates, top-left origin).
final class AXPositionTracker {
    private var observer: AXObserver?
    private let windowRef: WindowRef
    private let onMove: (CGRect) -> Void

    init(windowRef: WindowRef, onMove: @escaping (CGRect) -> Void) {
        self.windowRef = windowRef
        self.onMove    = onMove
    }

    func start() {
        let element  = windowRef.element
        let selfPtr  = Unmanaged.passUnretained(self).toOpaque()

        var obs: AXObserver?
        guard AXObserverCreate(windowRef.pid, { _, elem, _, ud in
            guard let ud else { return }
            let tracker = Unmanaged<AXPositionTracker>.fromOpaque(ud).takeUnretainedValue()
            tracker.readBounds(from: elem)
        }, &obs) == .success, let obs else { return }

        AXObserverAddNotification(obs, element, kAXWindowMovedNotification   as CFString, selfPtr)
        AXObserverAddNotification(obs, element, kAXWindowResizedNotification  as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    func stop() {
        guard let obs = observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = nil
    }

    private func readBounds(from element: AXUIElement) {
        var posRef:  CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute     as CFString, &sizeRef) == .success
        else { return }
        var pos  = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef  as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize,  &size)
        let bounds = CGRect(origin: pos, size: size)
        DispatchQueue.main.async { [weak self] in self?.onMove(bounds) }
    }
}

// MARK: - Coordinate helper

extension CGRect {
    /// Convert a CG-coordinate rect (origin top-left of main screen) to an
    /// AppKit NSRect (origin bottom-left of main screen).
    ///
    /// AppKit's unified coordinate space always uses the main screen height as
    /// the Y reference — even for windows on secondary monitors.
    static func cgToAppKit(_ rect: CGRect) -> NSRect {
        let mainH = NSScreen.main?.frame.height ?? 0
        return NSRect(x: rect.minX,
                      y: mainH - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }
}
