import AppKit
import ApplicationServices

/// A snapshot of a discoverable window, wrapping its AXUIElement and metadata.
struct WindowRef {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleId: String?
    var title: String
    var bounds: CGRect

    /// Returns a persistable identity for best-effort re-matching on next launch.
    var identity: WindowIdentity {
        WindowIdentity(bundleId: bundleId, appName: appName, title: title, bounds: bounds)
    }

    /// Returns false when the underlying AXUIElement is no longer valid.
    var isValid: Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return result != .invalidUIElement && result != .failure
    }

    /// Human-readable display string for the window list.
    var displayTitle: String {
        title.isEmpty ? "(untitled)" : title
    }
}

extension WindowRef: Equatable {
    static func == (lhs: WindowRef, rhs: WindowRef) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
}
