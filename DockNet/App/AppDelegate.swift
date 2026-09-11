import AppKit
import SwiftUI
import os

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.local.DockNet", category: "AppDelegate")
    private var testWindow: NSWindow?

    @MainActor
    public lazy var viewModel: StatusViewModel = StatusViewModel.makeConfiguredInstance()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let isUITesting = args.contains("--ui-testing")
        Self.logger.info("DockNet launched (uiTesting: \(isUITesting))")

        if args.contains("--test-notification") {
            handleTestNotification()
            return
        }

        if isUITesting {
            // For UI testing automation, use regular policy so the test window can be focused & queried
            NSApp.setActivationPolicy(.regular)
            setupTestHostWindow()
        } else {
            // Normal production operation: accessory agent app with no Dock icon
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func handleTestNotification() {
        Task { @MainActor in
            let auth = await viewModel.notificationManager.scheduler.authorizationStatus()
            if auth == .authorized || auth == .provisional {
                await viewModel.notificationManager.sendTestNotification()
                print(">>> [DOCKNET] Test notification delivered successfully.")
            } else if auth == .denied {
                print(">>> [DOCKNET] Notification permission is DENIED by macOS. Please enable notifications for DockNet in System Settings -> Notifications.")
            } else {
                print(">>> [DOCKNET] Notification permission is NOT DETERMINED. Requesting authorization...")
                let granted = await viewModel.notificationManager.scheduler.requestAuthorization()
                if granted {
                    await viewModel.notificationManager.sendTestNotification()
                    print(">>> [DOCKNET] Test notification delivered successfully.")
                } else {
                    print(">>> [DOCKNET] Notification permission was not granted.")
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private func setupTestHostWindow() {
        let contentView = MenuBarView(viewModel: viewModel)
            .frame(width: 300)

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 100, width: 310, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockNet Test Host"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.testWindow = window

        NSApp.activate(ignoringOtherApps: true)
        Self.logger.info("Test host window created and presented")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        Self.logger.info("DockNet terminating")
    }
}
