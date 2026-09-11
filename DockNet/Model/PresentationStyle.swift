import Foundation

/// Defines the user-selectable UI presentation style for DockNet.
public enum PresentationStyle: String, CaseIterable, Sendable {
    case compact
    case detailed
}

/// Lightweight owner and coordinator for user presentation style preferences.
public final class PresentationPreferences: @unchecked Sendable {
    public static let userDefaultsKey = "docknet.presentation.style"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current presentation style, defaulting to `.compact` if missing or invalid.
    public var style: PresentationStyle {
        get {
            guard let raw = defaults.string(forKey: Self.userDefaultsKey),
                  let parsed = PresentationStyle(rawValue: raw) else {
                return .compact
            }
            return parsed
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.userDefaultsKey)
        }
    }
}
