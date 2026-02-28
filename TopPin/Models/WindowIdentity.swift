import Foundation
import CoreGraphics

/// Persistable best-effort identity for a window, stored in UserDefaults.
/// Used to attempt auto-reconnect after app restarts.
struct WindowIdentity: Codable {
    let bundleId: String?
    let appName: String
    let titleHash: Int           // Hashed for privacy / size
    let boundsX: Double
    let boundsY: Double
    let boundsW: Double
    let boundsH: Double

    init(bundleId: String?, appName: String, title: String, bounds: CGRect) {
        self.bundleId  = bundleId
        self.appName   = appName
        self.titleHash = title.hashValue
        self.boundsX   = bounds.origin.x
        self.boundsY   = bounds.origin.y
        self.boundsW   = bounds.size.width
        self.boundsH   = bounds.size.height
    }

    var approximateBounds: CGRect {
        CGRect(x: boundsX, y: boundsY, width: boundsW, height: boundsH)
    }

    /// Fuzzy match: same bundle (or app name) AND overlapping bounds.
    func matches(_ ref: WindowRef) -> Bool {
        let bundleMatch: Bool = {
            if let mine = bundleId, let theirs = ref.bundleId {
                return mine == theirs
            }
            return appName == ref.appName
        }()
        let boundsClose = approximateBounds.insetBy(dx: -20, dy: -20).intersects(ref.bounds)
        return bundleMatch && boundsClose
    }
}
