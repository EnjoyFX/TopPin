import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.example.TopPin", category: "WindowEnumerator")

/// Lists windows for all running applications via Accessibility APIs.
class WindowEnumerator {

    // MARK: - Public

    /// Enumerates all accessible windows across all user-facing applications.
    func enumerateWindows() -> [WindowRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .flatMap { windows(for: $0) }
    }

    /// Returns all accessible windows for a single running application.
    func windows(for app: NSRunningApplication) -> [WindowRef] {
        let pid   = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &rawValue) == .success,
              let windowList = rawValue as? [AXUIElement]
        else { return [] }

        return windowList.compactMap { makeWindowRef(from: $0, app: app) }
    }

    // MARK: - Private

    private func makeWindowRef(from element: AXUIElement,
                               app: NSRunningApplication) -> WindowRef? {
        // Must be a standard window
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        guard (roleValue as? String) == kAXWindowRole as String else { return nil }

        // Title
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? ""

        // Position
        var posValue: CFTypeRef?
        var position = CGPoint.zero
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           let posValue {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        }

        // Size
        var sizeValue: CFTypeRef?
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        let bounds = CGRect(origin: position, size: size)

        return WindowRef(
            element:  element,
            pid:      app.processIdentifier,
            appName:  app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier,
            title:    title,
            bounds:   bounds
        )
    }
}
