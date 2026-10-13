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
        static let barMode = "barMode"
    }

    /// When clicking the arrow opens the bar below the menu bar instead of
    /// revealing hidden icons inline.
    enum BarMode: String, CaseIterable, Identifiable {
        case automatic, always, never
        var id: String { rawValue }
        var label: String {
            switch self {
            case .automatic: "On displays with a notch"
            case .always: "On every display"
            case .never: "Never"
            }
        }
    }

    /// Seconds the hidden section stays open before it collapses again.
    @Published var rehideDelay: Double {
        didSet { defaults.set(rehideDelay, forKey: Key.rehideDelay) }
    }

    /// Collapse the hidden section as soon as another app becomes active.
    @Published var rehideOnAppSwitch: Bool {
        didSet { defaults.set(rehideOnAppSwitch, forKey: Key.rehideOnAppSwitch) }
    }

    @Published var barMode: BarMode {
        didSet { defaults.set(barMode.rawValue, forKey: Key.barMode) }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    private init() {
        defaults.register(defaults: [
            Key.rehideDelay: 5.0,
            Key.rehideOnAppSwitch: true,
            Key.barMode: BarMode.automatic.rawValue,
        ])
        rehideDelay = defaults.double(forKey: Key.rehideDelay)
        rehideOnAppSwitch = defaults.bool(forKey: Key.rehideOnAppSwitch)
        barMode = BarMode(rawValue: defaults.string(forKey: Key.barMode) ?? "") ?? .automatic
    }
}
