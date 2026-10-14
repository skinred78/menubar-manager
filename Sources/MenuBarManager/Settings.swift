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
        static let hiddenBundleIDs = "hiddenBundleIDs"
    }

    /// Apps whose menu bar icons are hidden. On macOS 27 hiding works per
    /// app, so this is the hidden section.
    @Published var hiddenBundleIDs: Set<String> {
        didSet { defaults.set(hiddenBundleIDs.sorted(), forKey: Key.hiddenBundleIDs) }
    }

    /// Seconds hidden icons stay shown before they're hidden again.
    @Published var rehideDelay: Double {
        didSet { defaults.set(rehideDelay, forKey: Key.rehideDelay) }
    }

    /// Hide the icons again as soon as another app becomes active.
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
        hiddenBundleIDs = Set(defaults.stringArray(forKey: Key.hiddenBundleIDs) ?? [])
        rehideDelay = defaults.double(forKey: Key.rehideDelay)
        rehideOnAppSwitch = defaults.bool(forKey: Key.rehideOnAppSwitch)
    }
}
