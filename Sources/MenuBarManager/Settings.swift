import Foundation

/// User preferences, stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let rehideDelay = "rehideDelay"
        static let rehideOnAppSwitch = "rehideOnAppSwitch"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    /// Seconds the hidden section stays open before it collapses again.
    @Published var rehideDelay: Double {
        didSet { defaults.set(rehideDelay, forKey: Key.rehideDelay) }
    }

    /// Collapse the hidden section as soon as another app becomes active.
    @Published var rehideOnAppSwitch: Bool {
        didSet { defaults.set(rehideOnAppSwitch, forKey: Key.rehideOnAppSwitch) }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    private init() {
        defaults.register(defaults: [
            Key.rehideDelay: 5.0,
            Key.rehideOnAppSwitch: true,
        ])
        rehideDelay = defaults.double(forKey: Key.rehideDelay)
        rehideOnAppSwitch = defaults.bool(forKey: Key.rehideOnAppSwitch)
    }
}
