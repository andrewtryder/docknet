#if DEBUG
    import Foundation
    import os

    /// Deterministic network monitor for UI tests and mock simulations.
    /// Mutations and delivery use separate serial queues; the lock protects shared reads and delivery tokens.
    public final class MockNetworkMonitor: NetworkMonitoringProtocol, @unchecked Sendable {
        private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "MockNetworkMonitor")
        private let lock = NSLock()
        private let queue = DispatchQueue(label: "com.andrewtryder.docknet.mockwatcher", qos: .utility)
        private let deliveryQueue = DispatchQueue(label: "com.andrewtryder.docknet.mock-delivery", qos: .utility)
        private let queueKey = DispatchSpecificKey<Bool>()
        private var deliveryGeneration: UInt64 = 0
        private var _currentSnapshot: NetworkSnapshot
        private var callback: (@Sendable (NetworkSnapshot) -> Void)?
        private var isMonitoring = false
        private var timerSource: DispatchSourceTimer?
        private let stateFilePath: String?

        public var onSnapshotUpdated: (@Sendable (NetworkSnapshot) -> Void)? {
            get { lock.lock(); defer { lock.unlock() }; return callback }
            set { lock.lock(); defer { lock.unlock() }; callback = newValue }
        }

        public init(scenario: String = "wifi", stateFilePath: String? = nil) {
            self.stateFilePath = stateFilePath
            _currentSnapshot = Self.makeSnapshot(for: scenario)
            queue.setSpecific(key: queueKey, value: true)
        }

        deinit { stopMonitoring() }

        private func onQueue(_ operation: () -> Void) {
            if DispatchQueue.getSpecific(key: queueKey) != nil {
                operation()
            } else {
                queue.sync(execute: operation)
            }
        }

        public var currentSnapshot: NetworkSnapshot {
            lock.lock(); defer { lock.unlock() }; return _currentSnapshot
        }

        public func setSnapshot(_ snapshot: NetworkSnapshot) {
            onQueue {
                lock.lock()
                _currentSnapshot = snapshot
                lock.unlock()
                deliver(snapshot)
            }
        }

        public func setScenario(_ scenario: String) {
            setSnapshot(Self.makeSnapshot(for: scenario))
        }

        public func startMonitoring() {
            onQueue {
                guard !isMonitoring else { return }
                isMonitoring = true
                advanceDeliveryGeneration()
                if let path = stateFilePath {
                    setupFileWatcher(at: path)
                }
                deliver(currentSnapshot)
            }
        }

        public func stopMonitoring() {
            onQueue {
                isMonitoring = false
                advanceDeliveryGeneration()
                timerSource?.cancel()
                timerSource = nil
            }
        }

        public func refresh() {
            onQueue {
                if let path = stateFilePath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
                    setScenario(content.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    deliver(currentSnapshot)
                }
            }
        }

        private func advanceDeliveryGeneration() {
            lock.lock()
            deliveryGeneration &+= 1
            lock.unlock()
        }

        private func deliver(_ snapshot: NetworkSnapshot) {
            lock.lock()
            let generation = deliveryGeneration
            lock.unlock()
            deliveryQueue.async { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                let handler = self.deliveryGeneration == generation ? self.callback : nil
                self.lock.unlock()
                handler?(snapshot)
            }
        }

        private func setupFileWatcher(at path: String) {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            var lastContent = ""
            timer.schedule(deadline: .now(), repeating: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                guard let self = self, self.isMonitoring,
                      let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != lastContent, !trimmed.isEmpty {
                    lastContent = trimmed
                    Self.logger.info("MockNetworkMonitor read updated state file scenario: \(trimmed)")
                    self.setScenario(trimmed)
                }
            }
            timerSource = timer
            timer.resume()
        }
    }
#endif
