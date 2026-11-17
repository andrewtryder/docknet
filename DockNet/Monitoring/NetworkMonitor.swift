import Foundation
import os

/// Monitors SystemConfiguration and feeds snapshots into the NetworkStateMachine.
/// Snapshots arrive serially from the SC monitor; synchronous state and callback access use `lock`.
public final class NetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "NetworkMonitor")

    private let scMonitor: SystemConfigurationMonitor
    public let stateMachine: NetworkStateMachine

    private let lock = NSLock()
    private var _currentSnapshot: NetworkSnapshot
    private var callback: (@Sendable (NetworkSnapshot) -> Void)?
    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); defer { lock.unlock() }; callback = newValue }
    }

    public init(stateMachine: NetworkStateMachine = NetworkStateMachine()) {
        self.stateMachine = stateMachine
        scMonitor = SystemConfigurationMonitor(stateMachine: stateMachine)

        let emptyWifi = NetworkInterfaceInfo(bsdName: "en0", serviceName: "Wi-Fi", isLinkActive: false)
        _currentSnapshot = NetworkSnapshot(wiredInterfaces: [], wifi: emptyWifi)

        setupBindings()
    }

    public var currentSnapshot: NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _currentSnapshot
    }

    private func setupBindings() {
        scMonitor.onSnapshotUpdated = { [weak self] snapshot in
            guard let self = self else { return }
            self.handleNewSnapshot(snapshot)
        }
    }

    private func handleNewSnapshot(_ snapshot: NetworkSnapshot) {
        lock.lock()
        _currentSnapshot = snapshot
        lock.unlock()

        onSnapshotUpdated?(snapshot)
    }

    public func startMonitoring() {
        Self.logger.info("Starting network monitoring")
        scMonitor.start()
    }

    public func stopMonitoring() {
        Self.logger.info("Stopping network monitoring")
        scMonitor.stop()
    }

    public func refresh() {
        Self.logger.debug("Explicit refresh requested")
        scMonitor.requestRefresh()
    }
}
