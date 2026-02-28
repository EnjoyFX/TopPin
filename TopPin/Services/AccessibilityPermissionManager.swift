import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "AXPermission")

/// Manages Accessibility permission (TCC kTCCServiceAccessibility).
///
/// Key detail: `AXIsProcessTrusted()` only CHECKS the current trust state.
/// `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
/// additionally ensures the app appears in System Settings → Accessibility,
/// which is required before the user can toggle the switch.
class AccessibilityPermissionManager {

    // MARK: - Check (silent, no dialog)

    func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        logger.info("AXIsProcessTrusted = \(trusted)")
        return trusted
    }

    // MARK: - Register + open System Settings

    /// Registers the app in System Settings → Accessibility (shows it in the list)
    /// and then opens that pane so the user can toggle it on.
    func openSystemSettings() {
        // Registering the app in the AX list requires calling with prompt=true.
        // This is the ONLY reliable way to add the app to the Accessibility list.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        // Also open the pane directly (belt & suspenders)
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recheck

    /// Re-checks trust state after a short delay.
    /// On macOS 15 the TCC database update can take ~1-2 s to propagate.
    func recheckPermission(completion: @escaping (Bool) -> Void) {
        // Poll a few times to handle slow TCC propagation
        poll(attempts: 5, interval: 0.8, completion: completion)
    }

    private func poll(attempts: Int, interval: TimeInterval,
                      completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            let trusted = AXIsProcessTrusted()
            logger.info("Poll: AXIsProcessTrusted = \(trusted), attempts left = \(attempts - 1)")
            if trusted || attempts <= 1 {
                completion(trusted)
            } else {
                self.poll(attempts: attempts - 1, interval: interval, completion: completion)
            }
        }
    }
}
