import Foundation
import os
import UserNotifications

/// Protocol abstracting notification scheduling for full unit testability.
public protocol NotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func send(_ notification: DockNetNotification) async
}

/// Production notification scheduler utilizing macOS UserNotifications.
public struct UserNotificationsScheduler: NotificationScheduling {
    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    public func send(_ notification: DockNetNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        // Sound is disabled by default per specifications

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil // Immediate delivery
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger(subsystem: "com.andrewtryder.DockNet", category: "Notifications").error("Failed to add notification: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
    /// Mock notification scheduler for unit and UI automation testing. All mutable state is guarded by `lock`.
    public final class MockNotificationScheduler: @unchecked Sendable, NotificationScheduling {
        private let lock = NSLock()
        private var _authStatus: UNAuthorizationStatus
        private var _requestAuthResult = true
        private var _sentNotifications: [DockNetNotification] = []
        private var _requestCount = 0

        public var stubbedAuthStatus: UNAuthorizationStatus {
            get { lock.lock(); defer { lock.unlock() }; return _authStatus }
            set { lock.lock(); defer { lock.unlock() }; _authStatus = newValue }
        }

        public var stubbedRequestAuthResult: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _requestAuthResult }
            set { lock.lock(); defer { lock.unlock() }; _requestAuthResult = newValue }
        }

        public var sentNotifications: [DockNetNotification] {
            lock.lock(); defer { lock.unlock() }; return _sentNotifications
        }

        public var requestAuthorizationCallCount: Int {
            lock.lock(); defer { lock.unlock() }; return _requestCount
        }

        public init(status: UNAuthorizationStatus = .notDetermined) {
            _authStatus = status
        }

        public func requestAuthorization() async -> Bool {
            recordRequestAuthorization()
        }

        private func recordRequestAuthorization() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            _requestCount += 1
            if _requestAuthResult {
                _authStatus = .authorized
            }
            return _requestAuthResult
        }

        public func authorizationStatus() async -> UNAuthorizationStatus {
            getAuthStatus()
        }

        private func getAuthStatus() -> UNAuthorizationStatus {
            lock.lock(); defer { lock.unlock() }; return _authStatus
        }

        public func send(_ notification: DockNetNotification) async {
            recordNotification(notification)
        }

        private func recordNotification(_ notification: DockNetNotification) {
            lock.lock(); defer { lock.unlock() }; _sentNotifications.append(notification)
        }

        public func reset() {
            lock.lock()
            defer { lock.unlock() }
            _sentNotifications.removeAll()
            _requestCount = 0
        }
    }
#endif

/// Coordinates notification preferences, authorization states, debounce, deduplication, and scheduling.
/// Transition state is guarded by `lock`; preferences use thread-safe UserDefaults.
public final class NotificationManager: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "NotificationManager")

    public static let preferenceKey = "docknet.notifications.enabled"

    public let scheduler: any NotificationScheduling
    /// `nonisolated(unsafe)` scopes the concurrency bypass strictly to this immutable `UserDefaults` reference
    /// (assigned once in `init`); all preference reads/writes delegate to thread-safe `NSUserDefaults`.
    public nonisolated(unsafe) let userDefaults: UserDefaults

    private let lock = NSLock()
    private var _stablePrimary: PrimaryConnection?
    private var _pendingCandidate: PrimaryConnection?
    private var _debounceGeneration: UInt64 = 0
    private var _preferenceGeneration: UInt64 = 0
    private var _sequenceCounter: Int = 0
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.andrewtryder.docknet.notifications", qos: .utility)

    public init(
        scheduler: any NotificationScheduling = UserNotificationsScheduler(),
        userDefaults: UserDefaults = .standard,
        debounceInterval: TimeInterval = 1.0
    ) {
        self.scheduler = scheduler
        self.userDefaults = userDefaults
        self.debounceInterval = debounceInterval
    }

    public var isPreferenceEnabled: Bool {
        get {
            userDefaults.bool(forKey: Self.preferenceKey)
        }
        set {
            lock.lock()
            _preferenceGeneration &+= 1
            if userDefaults.bool(forKey: Self.preferenceKey) != newValue {
                _debounceGeneration &+= 1
                _pendingCandidate = nil
            }
            userDefaults.set(newValue, forKey: Self.preferenceKey)
            lock.unlock()
        }
    }

    public var previousPrimary: PrimaryConnection? {
        lock.lock()
        defer { lock.unlock() }
        return _stablePrimary
    }

    private func beginPreferenceChange(enabled: Bool) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        _preferenceGeneration &+= 1
        if !enabled {
            _debounceGeneration &+= 1
            _pendingCandidate = nil
            userDefaults.set(false, forKey: Self.preferenceKey)
        }
        return _preferenceGeneration
    }

    private func finishPreferenceChange(enabled: Bool, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard _preferenceGeneration == generation else { return }
        if userDefaults.bool(forKey: Self.preferenceKey) != enabled {
            _debounceGeneration &+= 1
            _pendingCandidate = nil
        }
        userDefaults.set(enabled, forKey: Self.preferenceKey)
    }

    /// Sets user preference, requesting authorization if enabling for the first time.
    @discardableResult
    public func setPreferenceEnabled(_ enabled: Bool) async -> UNAuthorizationStatus {
        let generation = beginPreferenceChange(enabled: enabled)
        let status = await scheduler.authorizationStatus()
        guard enabled else { return status }
        let resolvedStatus: UNAuthorizationStatus
        if status == .notDetermined {
            resolvedStatus = await scheduler.requestAuthorization() ? .authorized : .denied
        } else {
            resolvedStatus = status
        }
        finishPreferenceChange(enabled: resolvedStatus != .denied, generation: generation)
        return resolvedStatus
    }

    /// Processes an updated network snapshot with debounce and deduplication.
    public func processSnapshot(_ snapshot: NetworkSnapshot) {
        let currentPrimary = Self.extractPrimaryConnection(from: snapshot)

        lock.lock()
        // 1. Quiet initial startup
        guard let stable = _stablePrimary else {
            Self.logger.info("Initial network snapshot recorded. Primary: \(currentPrimary.bsdName, privacy: .public)")
            _stablePrimary = currentPrimary
            lock.unlock()
            return
        }

        // 2. If notifications are disabled, keep stable primary updated without timers or debounce overhead
        guard isPreferenceEnabled else {
            _stablePrimary = currentPrimary
            _debounceGeneration &+= 1
            _pendingCandidate = nil
            lock.unlock()
            return
        }

        // 3. If the new snapshot matches the existing stable primary:
        if currentPrimary == stable {
            if _pendingCandidate != nil {
                // Cancel any pending transition back to a transient primary (A -> B -> A).
                _debounceGeneration &+= 1
                _pendingCandidate = nil
                Self.logger.info("Transition cancelled: primary returned to stable \(stable.bsdName, privacy: .public)")
            }
            lock.unlock()
            return
        }

        // 4. New candidate differs from stable primary (A -> B or A -> B -> C)
        _debounceGeneration &+= 1
        _pendingCandidate = currentPrimary

        // If debounce is 0 (test mode), process immediately
        if debounceInterval <= 0 {
            _stablePrimary = currentPrimary
            let transition = ConnectionTransition(from: stable, to: currentPrimary)
            _sequenceCounter += 1
            let seq = _sequenceCounter
            let generation = _debounceGeneration
            lock.unlock()

            Task { [weak self] in
                await self?.evaluateAndSend(transition: transition, sequence: seq, generation: generation)
            }
            return
        }

        // 5. Schedule debounced transition using generation token
        let generation = _debounceGeneration
        let candidate = currentPrimary
        lock.unlock()

        queue.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            guard self._debounceGeneration == generation else {
                self.lock.unlock()
                return
            }
            guard let from = self._stablePrimary, from != candidate else {
                self._pendingCandidate = nil
                self.lock.unlock()
                return
            }
            self._stablePrimary = candidate
            self._pendingCandidate = nil
            self._sequenceCounter += 1
            let seq = self._sequenceCounter
            self.lock.unlock()

            let transition = ConnectionTransition(from: from, to: candidate)
            Task {
                await self.evaluateAndSend(transition: transition, sequence: seq, generation: generation)
            }
        }
    }

    private func isCurrent(generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _debounceGeneration == generation && isPreferenceEnabled
    }

    private func evaluateAndSend(transition: ConnectionTransition, sequence: Int, generation: UInt64) async {
        guard isPreferenceEnabled else {
            Self.logger.debug("Transition ignored: notifications preference is disabled")
            return
        }

        let authStatus = await scheduler.authorizationStatus()
        guard authStatus == .authorized || authStatus == .provisional else {
            Self.logger.notice("Transition ignored: authorization status is \(authStatus.rawValue)")
            return
        }

        guard isCurrent(generation: generation),
              let notification = NotificationFormatter.format(transition: transition, sequence: sequence)
        else {
            return
        }

        Self.logger.info("Sending transition notification: \(notification.title, privacy: .public) - \(notification.body, privacy: .public)")
        await scheduler.send(notification)
    }

    /// Sends a manual test notification.
    public func sendTestNotification() async {
        let testNotification = DockNetNotification(
            identifier: "docknet.test-notification.\(Int(Date().timeIntervalSince1970))",
            title: "DockNet Notifications",
            body: "Notifications are working."
        )
        await scheduler.send(testNotification)
    }

    public func resetState() {
        lock.lock()
        defer { lock.unlock() }
        _debounceGeneration &+= 1
        _pendingCandidate = nil
        _stablePrimary = nil
    }

    private static func extractPrimaryConnection(from snapshot: NetworkSnapshot) -> PrimaryConnection {
        switch snapshot.physicalTransport.kind {
        case .ethernet:
            let bsd = snapshot.physicalTransport.bsdName ?? "ethernet"
            let name = snapshot.physicalTransport.serviceName ?? snapshot.activePrimaryWiredInterface?.serviceName ?? "Ethernet"
            let ip = snapshot.physicalTransport.ipv4Address ?? snapshot.activePrimaryWiredInterface?.ipv4Address
            return PrimaryConnection(
                type: .ethernet,
                serviceName: name,
                bsdName: bsd,
                ipv4Address: ip
            )
        case .wifi:
            return PrimaryConnection(
                type: .wifi,
                serviceName: snapshot.wifi.serviceName,
                bsdName: snapshot.wifi.bsdName,
                ipv4Address: snapshot.wifi.primaryIPv4Address
            )
        case .none:
            return PrimaryConnection(
                type: .none,
                serviceName: nil,
                bsdName: "none",
                ipv4Address: nil
            )
        }
    }
}
