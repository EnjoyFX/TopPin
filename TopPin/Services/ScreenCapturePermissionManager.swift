import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "SCKPermission")

/// Manages Screen Recording permission using public CoreGraphics APIs.
///
/// `CGPreflightScreenCaptureAccess()` – checks silently, no dialog.
/// `CGRequestScreenCaptureAccess()`   – shows the system dialog once.
class ScreenCapturePermissionManager {

    /// Returns true if Screen Recording is already granted (no dialog shown).
    static func hasPermission() -> Bool {
        let result = CGPreflightScreenCaptureAccess()
        logger.info("CGPreflightScreenCaptureAccess = \(result)")
        return result
    }

    /// Shows the system permission dialog (only once; subsequent calls are no-ops
    /// until the user changes the setting in System Settings).
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Opens the Screen Recording pane in System Settings.
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
