import Foundation

/// Thin UserDefaults wrapper; all access is on the main thread.
class PreferencesStore {

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let interval          = "toppin.interval"
        static let allowFocusSteal   = "toppin.allowFocusSteal"
        static let lastWindowIdent   = "toppin.lastWindowIdentity"
    }

    // MARK: - Interval (200 ms – 1 500 ms)

    var interval: Double {
        get {
            let v = defaults.double(forKey: Key.interval)
            return v == 0 ? 0.4 : max(0.2, min(1.5, v))
        }
        set { defaults.set(max(0.2, min(1.5, newValue)), forKey: Key.interval) }
    }

    // MARK: - Toggles

    var allowFocusSteal: Bool {
        get { defaults.bool(forKey: Key.allowFocusSteal) }
        set { defaults.set(newValue, forKey: Key.allowFocusSteal) }
    }

    // MARK: - Last window identity

    var lastWindowIdentity: WindowIdentity? {
        get {
            guard let data = defaults.data(forKey: Key.lastWindowIdent) else { return nil }
            return try? JSONDecoder().decode(WindowIdentity.self, from: data)
        }
        set {
            if let value = newValue,
               let data  = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: Key.lastWindowIdent)
            } else {
                defaults.removeObject(forKey: Key.lastWindowIdent)
            }
        }
    }
}
