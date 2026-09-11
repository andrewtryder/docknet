import Foundation
import UserNotifications
import os

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
            Logger(subsystem: "com.local.DockNet", category: "Notifications").error("Failed to add notification: \(error.localizedDescription)")
        }
    }
}

/// Mock notification scheduler for unit and UI automation testing.
public final class MockNotificationScheduler: @unchecked Sendable, NotificationScheduling {
    private let lock = NSLock()
    public var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    public var stubbedRequestAuthResult: Bool = true
    public private(set) var sentNotifications: [DockNetNotification] = []
    public private(set) var requestAuthorizationCallCount: Int = 0

    public init(status: UNAuthorizationStatus = .notDetermined) {
        self.stubbedAuthStatus = status
    }

    public func requestAuthorization() async -> Bool {
        recordRequestAuthorization()
    }

    private func recordRequestAuthorization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        requestAuthorizationCallCount += 1
        if stubbedRequestAuthResult {
            stubbedAuthStatus = .authorized
        }
        return stubbedRequestAuthResult
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        getAuthStatus()
    }

    private func getAuthStatus() -> UNAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return stubbedAuthStatus
    }

    public func send(_ notification: DockNetNotification) async {
        recordNotification(notification)
    }

    private func recordNotification(_ notification: DockNetNotification) {
        lock.lock()
        defer { lock.unlock() }
        sentNotifications.append(notification)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        sentNotifications.removeAll()
        requestAuthorizationCallCount = 0
    }
}

/// Coordinates notification preferences, authorization states, debounce, deduplication, and scheduling.
public final class NotificationManager: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "NotificationManager")

    public static let preferenceKey = "docknet.notifications.enabled"

    public let scheduler: any NotificationScheduling
    public let userDefaults: UserDefaults

    private let lock = NSLock()
    private var _previousPrimary: PrimaryConnection? = nil
    private var _pendingWorkItem: DispatchWorkItem? = nil
    private var _sequenceCounter: Int = 0
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.local.docknet.notifications", qos: .utility)

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
            userDefaults.set(newValue, forKey: Self.preferenceKey)
        }
    }

    public var previousPrimary: PrimaryConnection? {
        lock.lock()
        defer { lock.unlock() }
        return _previousPrimary
    }

    /// Sets user preference, requesting authorization if enabling for the first time.
    @discardableResult
    public func setPreferenceEnabled(_ enabled: Bool) async -> UNAuthorizationStatus {
        if enabled {
            let currentStatus = await scheduler.authorizationStatus()
            if currentStatus == .notDetermined {
                let granted = await scheduler.requestAuthorization()
                if granted {
                    isPreferenceEnabled = true
                    return .authorized
                } else {
                    isPreferenceEnabled = false
                    return .denied
                }
            } else if currentStatus == .denied {
                isPreferenceEnabled = false
                return .denied
            } else {
                isPreferenceEnabled = true
                return currentStatus
            }
        } else {
            isPreferenceEnabled = false
            return await scheduler.authorizationStatus()
        }
    }

    /// Processes an updated network snapshot with debounce and deduplication.
    public func processSnapshot(_ snapshot: NetworkSnapshot) {
        let currentPrimary = Self.extractPrimaryConnection(from: snapshot)

        lock.lock()
        // 1. Quiet initial startup
        guard let prev = _previousPrimary else {
            Self.logger.info("Initial network snapshot recorded. Primary: \(currentPrimary.bsdName, privacy: .public)")
            _previousPrimary = currentPrimary
            lock.unlock()
            return
        }

        // 2. No transition if identical
        if prev == currentPrimary {
            lock.unlock()
            return
        }

        // 3. Cancel existing debounce timer
        _pendingWorkItem?.cancel()
        _pendingWorkItem = nil

        // If debounce is 0 (test mode), process immediately
        if debounceInterval <= 0 {
            _previousPrimary = currentPrimary
            let transition = ConnectionTransition(from: prev, to: currentPrimary)
            _sequenceCounter += 1
            let seq = _sequenceCounter
            lock.unlock()

            Task { [weak self] in
                await self?.evaluateAndSend(transition: transition, sequence: seq)
            }
            return
        }

        // 4. Schedule debounced transition
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let finalPrev = self._previousPrimary
            self._previousPrimary = currentPrimary
            self._sequenceCounter += 1
            let seq = self._sequenceCounter
            self.lock.unlock()

            if let from = finalPrev, from != currentPrimary {
                let transition = ConnectionTransition(from: from, to: currentPrimary)
                Task {
                    await self.evaluateAndSend(transition: transition, sequence: seq)
                }
            }
        }

        _pendingWorkItem = workItem
        lock.unlock()

        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func evaluateAndSend(transition: ConnectionTransition, sequence: Int) async {
        guard isPreferenceEnabled else {
            Self.logger.debug("Transition ignored: notifications preference is disabled")
            return
        }

        let authStatus = await scheduler.authorizationStatus()
        guard authStatus == .authorized || authStatus == .provisional else {
            Self.logger.notice("Transition ignored: authorization status is \(authStatus.rawValue)")
            return
        }

        guard let notification = NotificationFormatter.format(transition: transition, sequence: sequence) else {
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
        _pendingWorkItem?.cancel()
        _pendingWorkItem = nil
        _previousPrimary = nil
    }

    private static func extractPrimaryConnection(from snapshot: NetworkSnapshot) -> PrimaryConnection {
        if snapshot.actualPrimaryIsWired, let wired = snapshot.activePrimaryWiredInterface {
            return PrimaryConnection(
                type: .ethernet,
                serviceName: wired.serviceName,
                bsdName: wired.bsdName,
                ipv4Address: wired.ipv4Address
            )
        } else if snapshot.isWifiPrimary {
            return PrimaryConnection(
                type: .wifi,
                serviceName: snapshot.wifi.serviceName,
                bsdName: snapshot.wifi.bsdName,
                ipv4Address: snapshot.wifi.primaryIPv4Address
            )
        } else if let primaryBSD = snapshot.primaryInterface, !primaryBSD.isEmpty {
            return PrimaryConnection(
                type: .other,
                serviceName: snapshot.primaryServiceName,
                bsdName: primaryBSD,
                ipv4Address: nil
            )
        } else {
            return PrimaryConnection(
                type: .none,
                serviceName: nil,
                bsdName: "none",
                ipv4Address: nil
            )
        }
    }
}
