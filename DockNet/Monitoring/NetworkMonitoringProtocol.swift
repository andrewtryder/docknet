import Foundation

/// Protocol defining network monitoring capabilities for injection and testing.
public protocol NetworkMonitoringProtocol: AnyObject, Sendable {
    /// Handler called when a new snapshot is captured.
    var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)? { get set }

    /// Returns the most recent snapshot.
    var currentSnapshot: NetworkSnapshot { get }

    /// Starts observing system network events.
    func startMonitoring()

    /// Stops observing system network events.
    func stopMonitoring()

    /// Requests an immediate snapshot evaluation.
    func refresh()
}
