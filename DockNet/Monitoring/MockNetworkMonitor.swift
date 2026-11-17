import Foundation
import os

/// Deterministic network monitor for UI tests and mock simulations.
public final class MockNetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "MockNetworkMonitor")

    private let lock = NSLock()
    private var _currentSnapshot: NetworkSnapshot
    private var isMonitoring: Bool = false
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var timerSource: DispatchSourceTimer?
    private let stateFilePath: String?

    public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)?

    public init(scenario: String = "wifi", stateFilePath: String? = nil) {
        self.stateFilePath = stateFilePath
        _currentSnapshot = Self.makeSnapshot(for: scenario)
    }

    public var currentSnapshot: NetworkSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _currentSnapshot
    }

    public func setSnapshot(_ snapshot: NetworkSnapshot) {
        lock.lock()
        _currentSnapshot = snapshot
        lock.unlock()

        Self.logger.info("MockNetworkMonitor snapshot updated manually")
        onSnapshotUpdated?(snapshot)
    }

    public func setScenario(_ scenario: String) {
        let snapshot = Self.makeSnapshot(for: scenario)
        setSnapshot(snapshot)
    }

    public func startMonitoring() {
        lock.lock()
        guard !isMonitoring else {
            lock.unlock()
            return
        }
        isMonitoring = true
        lock.unlock()

        Self.logger.info("MockNetworkMonitor started")

        // If a state file path is provided, watch it for live dynamic transitions
        if let path = stateFilePath {
            setupFileWatcher(at: path)
        }

        // Fire initial snapshot
        let initial = currentSnapshot
        onSnapshotUpdated?(initial)
    }

    public func stopMonitoring() {
        lock.lock()
        guard isMonitoring else {
            lock.unlock()
            return
        }
        isMonitoring = false
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        timerSource?.cancel()
        timerSource = nil
        lock.unlock()

        Self.logger.info("MockNetworkMonitor stopped")
    }

    public func refresh() {
        if let path = stateFilePath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            setScenario(trimmed)
        } else {
            let current = currentSnapshot
            onSnapshotUpdated?(current)
        }
    }

    private func setupFileWatcher(at path: String) {
        // Poll every 100ms for state file changes in UI testing mode
        let queue = DispatchQueue(label: "com.andrewtryder.docknet.mockwatcher", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        var lastContent = ""

        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self, let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != lastContent, !trimmed.isEmpty {
                lastContent = trimmed
                Self.logger.info("MockNetworkMonitor read updated state file scenario: \(trimmed)")
                self.setScenario(trimmed)
            }
        }
        timer.resume()
        timerSource = timer
    }
}
