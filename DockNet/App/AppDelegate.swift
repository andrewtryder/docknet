import AppKit
import os

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.andrewtryder.DockNet", category: "AppDelegate")
    private static var strongDelegate: AppDelegate?

    public nonisolated static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            strongDelegate = delegate
            app.delegate = delegate
            app.run()
        }
    }

    public var networkMonitor: (any NetworkMonitoringProtocol)!
    public var notificationManager: NotificationManager!
    public var loginItemManager: LoginItemManager!
    public var statusItemController: StatusItemController?
    private var testWindow: NSWindow?
    private var testHostController: TestHostViewController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        let isUITesting = args.contains("--ui-testing")
        let isLiveMode = args.contains("--live-mode")

        Self.logger.info("DockNet launched (uiTesting: \(isUITesting), liveMode: \(isLiveMode))")

        if args.contains("--test-notification") {
            handleTestNotification()
            return
        }

        // Initialize managers
        self.loginItemManager = LoginItemManager()

        if isUITesting && !isLiveMode {
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

            let mockMonitor = MockNetworkMonitor(scenario: scenario, stateFilePath: stateFile)
            self.networkMonitor = mockMonitor

            let mockScheduler = MockNotificationScheduler(status: .notDetermined)
            self.notificationManager = NotificationManager(
                scheduler: mockScheduler,
                userDefaults: UserDefaults(suiteName: "com.andrewtryder.docknet.tests") ?? .standard,
                debounceInterval: 0
            )

            AboutWindowController.shared.urlOpener = MockURLOpener()
        } else {
            let monitor = NetworkMonitor()
            self.networkMonitor = monitor
            self.notificationManager = NotificationManager()
            self.statusItemController = StatusItemController(
                networkMonitor: monitor,
                notificationManager: notificationManager,
                loginItemManager: loginItemManager
            )
        }

        // Bind snapshot updates
        networkMonitor.onSnapshotUpdated = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.notificationManager.processSnapshot(snapshot)
                self.statusItemController?.updateSnapshot(snapshot)
                self.testHostController?.update(with: snapshot)
            }
        }

        networkMonitor.startMonitoring()

        if isUITesting {
            NSApp.setActivationPolicy(.regular)
            setupTestHostWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func setupTestHostWindow() {
        let hostVC = TestHostViewController(
            networkMonitor: networkMonitor,
            notificationManager: notificationManager,
            loginItemManager: loginItemManager
        )
        self.testHostController = hostVC

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 100, width: 340, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockNet Test Host"
        window.contentViewController = hostVC
        window.makeKeyAndOrderFront(nil)
        self.testWindow = window

        NSApp.activate(ignoringOtherApps: true)
        Self.logger.info("Test host window created and presented")
    }

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

    public func applicationWillTerminate(_ notification: Notification) {
        Self.logger.info("DockNet terminating")
        networkMonitor?.stopMonitoring()
    }
}
