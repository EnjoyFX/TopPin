import AppKit
import ApplicationServices
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "PinnedWindowController")

// MARK: - State

enum PinState: Equatable {
    case idle
    case pinning(WindowRef)
    case error(String)

    static func == (lhs: PinState, rhs: PinState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.pinning(let a), .pinning(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Controller

/// Keeps a target window on top.
///
/// **Overlay mode** (preferred, requires Screen Recording permission):
///   Creates a TopPin-owned NSWindow at `.floating` level that renders a live
///   SCStream of the target window.  Because the overlay is our own window we
///   can set its level freely — no private APIs, no focus stealing, no blinking.
///   Mouse/scroll events on the overlay are forwarded to the original process
///   via CGEvent.postToPid().  The window title bar, close/minimise buttons etc.
///   all work through event forwarding.
///
/// **AX fallback mode** (when Screen Recording is not granted):
///   Calls kAXRaiseAction on a timer.  With `allowFocusSteal` enabled it also
///   activates the owning app to guarantee cross-app ordering.
@MainActor
final class PinnedWindowController {

    // MARK: State

    private(set) var state: PinState = .idle {
        didSet { stateObservers.forEach { $0(state) } }
    }

    private var stateObservers: [(PinState) -> Void] = []

    /// Appends an observer that is called on the main thread whenever pin state changes.
    /// Multiple callers can subscribe without overwriting each other.
    func addStateObserver(_ handler: @escaping (PinState) -> Void) {
        stateObservers.append(handler)
    }

    // MARK: Config

    let preferences: PreferencesStore

    // MARK: Private – overlay

    private var overlayController: FloatingOverlayWindowController?

    // MARK: Private – AX fallback

    private var loopTask: Task<Void, Never>?
    private var workspaceObserver: Any?
    private var isRaising = false

    // MARK: Init

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    // MARK: - Public API

    var isPinned: Bool {
        if case .pinning = state { return true }
        return false
    }

    var pinnedWindow: WindowRef? {
        if case .pinning(let ref) = state { return ref }
        return nil
    }

    func pin(_ windowRef: WindowRef) {
        unpin()
        state = .pinning(windowRef)
        preferences.lastWindowIdentity = windowRef.identity
        logger.info("Pin requested: \(windowRef.appName) – \(windowRef.title)")

        Task {
            guard case .pinning = self.state else { return }

            if ScreenCapturePermissionManager.hasPermission() {
                // Already granted – go straight to overlay mode
                await self.startOverlayMode(windowRef)
            } else {
                // Request permission (shows dialog once), then check again
                logger.info("Screen Recording not granted – requesting")
                ScreenCapturePermissionManager.requestPermission()

                // Give the user a moment to respond to the dialog
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard case .pinning = self.state else { return }

                if ScreenCapturePermissionManager.hasPermission() {
                    await self.startOverlayMode(windowRef)
                } else {
                    logger.info("Screen Recording denied – using AX fallback")
                    self.startAXFallback(windowRef)
                }
            }
        }
    }

    func unpin() {
        // Stop overlay
        if let overlay = overlayController {
            Task { await overlay.stopCapture() }
            overlayController = nil
        }
        // Stop AX fallback
        loopTask?.cancel()
        loopTask = nil
        removeWorkspaceObserver()
        isRaising = false

        if case .pinning = state { state = .idle }
        logger.info("Unpinned")
    }

    func togglePin(_ windowRef: WindowRef? = nil) {
        switch state {
        case .pinning:            unpin()
        case .idle, .error:
            if let ref = windowRef ?? pinnedWindow { pin(ref) }
        }
    }

    // MARK: - Overlay mode

    private func startOverlayMode(_ windowRef: WindowRef) async {
        let overlay = FloatingOverlayWindowController(windowRef: windowRef)
        overlay.onWindowGone = { [weak self] in
            self?.unpin()
            self?.state = .error("Target window no longer exists")
        }
        overlayController = overlay

        do {
            try await overlay.startCapture()
            logger.info("Overlay mode active")
        } catch {
            logger.warning("Overlay mode failed (\(error.localizedDescription)) – falling back to AX")
            overlayController = nil
            startAXFallback(windowRef)
        }
    }

    // MARK: - AX fallback mode

    private func startAXFallback(_ windowRef: WindowRef) {
        performRaise(windowRef)

        if preferences.allowFocusSteal {
            subscribeWorkspaceNotifications(for: windowRef)
        }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: UInt64(self.preferences.interval * 1_000_000_000)) }
                catch { break }
                guard !Task.isCancelled else { break }
                self.performRaise(windowRef)
            }
        }
    }

    private func subscribeWorkspaceNotifications(for windowRef: WindowRef) {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, !self.isRaising else { return }
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != windowRef.pid,
                      app.bundleIdentifier  != Bundle.main.bundleIdentifier
                else { return }
                self.performRaise(windowRef)
            }
        }
    }

    private func removeWorkspaceObserver() {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }

    private func performRaise(_ windowRef: WindowRef) {
        guard !isRaising else { return }

        var probe: CFTypeRef?
        let check = AXUIElementCopyAttributeValue(windowRef.element, kAXTitleAttribute as CFString, &probe)
        guard check != .invalidUIElement, check != .failure else {
            unpin(); state = .error("Target window no longer exists"); return
        }

        AXUIElementPerformAction(windowRef.element, kAXRaiseAction as CFString)

        guard preferences.allowFocusSteal else { return }

        isRaising = true
        NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == windowRef.pid })?
            .activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRaising = false
        }
    }
}
