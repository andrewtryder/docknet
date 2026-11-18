import AppKit
import os

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "AppDelegate")
    private static var strongDelegate: AppDelegate?

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        strongDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    public var networkMonitor: (any NetworkMonitoringProtocol)?
    public var notificationManager: NotificationManager?
    public var loginItemManager: LoginItemManager?
    public var statusItemController: StatusItemController?
    private var isTerminating = false
    #if DEBUG
        private var testWindow: NSWindow?
        private var testHostController: TestHostViewController?
    #endif

    public func applicationDidFinishLaunching(_: Notification) {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("--test-notification") {
            Self.logger.info("DockNet launched (--test-notification)")
            handleTestNotification()
            return
        }

        let loginMgr = LoginItemManager()
        loginItemManager = loginMgr

        #if DEBUG
            let env = ProcessInfo.processInfo.environment
            let isUITesting = args.contains("--ui-testing")
            let isLiveMode = args.contains("--live-mode")

            Self.logger.info("DockNet launched (uiTesting: \(isUITesting), liveMode: \(isLiveMode))")

            let monitor: any NetworkMonitoringProtocol
            let notifMgr: NotificationManager

            if isUITesting, !isLiveMode {
                var scenario = "wifi"
                var stateFile: String? = nil

                for arg in args {
                    if arg.hasPrefix("--state=") {
                        scenario = String(arg.dropFirst("--state=".count))
                    } else if arg.hasPrefix("--state-file=") {
                        stateFile = String(arg.dropFirst("--state-file=".count))
                    }
                }
                if let envScenario = env["DOCKNET_TEST_NETWORK_STATE"] {
                    scenario = envScenario
                }
                if let envFile = env["DOCKNET_TEST_STATE_FILE"] {
                    stateFile = envFile
                }

                monitor = MockNetworkMonitor(scenario: scenario, stateFilePath: stateFile)

                let mockScheduler = MockNotificationScheduler(status: .notDetermined)
                notifMgr = NotificationManager(
                    scheduler: mockScheduler,
                    userDefaults: UserDefaults(suiteName: "com.andrewtryder.docknet.tests") ?? .standard,
                    debounceInterval: 0
                )

                AboutWindowController.shared.urlOpener = MockURLOpener()
            } else {
                let liveMonitor = NetworkMonitor()
                monitor = liveMonitor
                notifMgr = NotificationManager()
                statusItemController = StatusItemController(
                    networkMonitor: liveMonitor,
                    notificationManager: notifMgr,
                    loginItemManager: loginMgr
                )
            }

            networkMonitor = monitor
            notificationManager = notifMgr

            monitor.onSnapshotUpdated = { [weak self] snapshot in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isTerminating else { return }
                    self.notificationManager?.processSnapshot(snapshot)
                    self.statusItemController?.updateSnapshot(snapshot)
                    self.testHostController?.update(with: snapshot)
                }
            }

            monitor.startMonitoring()

            if isUITesting {
                NSApp.setActivationPolicy(.regular)
                setupTestHostWindow(monitor: monitor, notificationManager: notifMgr, loginItemManager: loginMgr)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        #else
            Self.logger.info("DockNet launched")

            let monitor = NetworkMonitor()
            let notifMgr = NotificationManager()
            networkMonitor = monitor
            notificationManager = notifMgr
            statusItemController = StatusItemController(
                networkMonitor: monitor,
                notificationManager: notifMgr,
                loginItemManager: loginMgr
            )

            monitor.onSnapshotUpdated = { [weak self] snapshot in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isTerminating else { return }
                    self.notificationManager?.processSnapshot(snapshot)
                    self.statusItemController?.updateSnapshot(snapshot)
                }
            }

            monitor.startMonitoring()
            NSApp.setActivationPolicy(.accessory)
        #endif
    }

    #if DEBUG
        private func setupTestHostWindow(
            monitor: any NetworkMonitoringProtocol,
            notificationManager: NotificationManager,
            loginItemManager: LoginItemManager
        ) {
            let hostVC = TestHostViewController(
                networkMonitor: monitor,
                notificationManager: notificationManager,
                loginItemManager: loginItemManager
            )
            testHostController = hostVC

            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 100, width: 340, height: 750),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DockNet Test Host"
            window.contentViewController = hostVC
            window.makeKeyAndOrderFront(nil)
            testWindow = window

            NSApp.activate(ignoringOtherApps: true)
            Self.logger.info("Test host window created and presented")
        }
    #endif

    private func handleTestNotification() {
        let notificationMgr = NotificationManager()
        Task { @MainActor in
            let auth = await notificationMgr.scheduler.authorizationStatus()
            if auth == .authorized || auth == .provisional {
                await notificationMgr.sendTestNotification()
                print(">>> [DOCKNET] Test notification delivered successfully.")
            } else if auth == .denied {
                print(">>> [DOCKNET] Notification permission is DENIED by macOS. Please enable notifications for DockNet in System Settings -> Notifications.")
            } else {
                print(">>> [DOCKNET] Notification permission is NOT DETERMINED. Requesting authorization...")
                let granted = await notificationMgr.scheduler.requestAuthorization()
                if granted {
                    await notificationMgr.sendTestNotification()
                    print(">>> [DOCKNET] Test notification delivered successfully.")
                } else {
                    print(">>> [DOCKNET] Notification permission was not granted.")
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            NSApp.terminate(nil)
        }
    }

    public func applicationWillTerminate(_: Notification) {
        Self.logger.info("DockNet terminating")
        isTerminating = true
        networkMonitor?.stopMonitoring()
    }
}
