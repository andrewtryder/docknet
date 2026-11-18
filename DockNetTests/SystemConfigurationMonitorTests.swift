@testable import DockNet
import XCTest

final class SystemConfigurationMonitorTests: XCTestCase {
    func testIPv6PrimaryFallbackAndIPv4Precedence() {
        let ipv6: [String: Any] = ["PrimaryInterface": "en6", "PrimaryService": "v6-service"]
        let ipv4: [String: Any] = ["PrimaryInterface": "en0", "PrimaryService": "v4-service"]
        let ipv6Primary = SystemConfigurationMonitor.selectPrimary(ipv4: nil, ipv6: ipv6)
        XCTAssertEqual(ipv6Primary.interface, "en6")
        XCTAssertEqual(ipv6Primary.service, "v6-service")
        let dualStack = SystemConfigurationMonitor.selectPrimary(ipv4: ipv4, ipv6: ipv6)
        XCTAssertEqual(dualStack.interface, "en0")
        XCTAssertEqual(dualStack.service, "v4-service")
        XCTAssertNil(SystemConfigurationMonitor.selectPrimary(ipv4: nil, ipv6: nil).interface)
    }

    func testStartStopAndRestartDeliverFreshInitialSnapshot() {
        let monitor = SystemConfigurationMonitor()
        let initial = expectation(description: "initial snapshot")
        monitor.onSnapshotUpdated = { _ in initial.fulfill() }
        monitor.start()
        monitor.start()
        wait(for: [initial], timeout: 5)
        monitor.stop()
        monitor.stop()
        let restarted = expectation(description: "restarted snapshot")
        monitor.onSnapshotUpdated = { _ in restarted.fulfill() }
        monitor.start()
        wait(for: [restarted], timeout: 5)
        monitor.stop()
    }

    @MainActor func testMockCallbackCanSynchronouslyReachMainAfterStart() async {
        let monitor = MockNetworkMonitor()
        let delivered = expectation(description: "mock callback reached main")
        monitor.onSnapshotUpdated = { _ in DispatchQueue.main.sync { delivered.fulfill() } }
        monitor.startMonitoring()
        await fulfillment(of: [delivered], timeout: 5)
        monitor.stopMonitoring()
    }

    @MainActor func testCallbackCanSynchronouslyReachMainAfterStart() async {
        let monitor = SystemConfigurationMonitor()
        let delivered = expectation(description: "callback reached main")
        monitor.onSnapshotUpdated = { _ in
            DispatchQueue.main.sync { delivered.fulfill() }
        }
        monitor.start()
        await fulfillment(of: [delivered], timeout: 5)
        monitor.stop()
    }

    func testStoppedGenerationDoesNotDeliverQueuedSnapshot() {
        let monitor = SystemConfigurationMonitor()
        let entered = expectation(description: "first callback entered")
        let stale = expectation(description: "queued old callback")
        stale.isInverted = true
        let unblock = DispatchSemaphore(value: 0)
        monitor.onSnapshotUpdated = { _ in
            entered.fulfill()
            _ = unblock.wait(timeout: .now() + 5)
        }
        monitor.start()
        wait(for: [entered], timeout: 5)
        monitor.stop()
        monitor.onSnapshotUpdated = { _ in stale.fulfill() }
        monitor.start()
        monitor.stop()
        unblock.signal()
        wait(for: [stale], timeout: 0.2)
    }

    func testCallbackCanStopMonitorWithoutDeadlock() {
        let monitor = SystemConfigurationMonitor()
        let stopped = expectation(description: "stopped inside callback")
        monitor.onSnapshotUpdated = { [weak monitor] _ in
            monitor?.stop()
            stopped.fulfill()
        }
        monitor.start()
        wait(for: [stopped], timeout: 5)
        monitor.stop()
    }

    func testMonitorAndNetworkMonitorDeallocateWithoutLeaks() {
        final class WeakBox<T: AnyObject> {
            weak var value: T?
        }

        let scBox = WeakBox<SystemConfigurationMonitor>()
        let nmBox = WeakBox<NetworkMonitor>()

        func runMonitorCycle() {
            let scDone = expectation(description: "sc monitor delivered snapshot")
            let sc = SystemConfigurationMonitor()
            scBox.value = sc
            sc.onSnapshotUpdated = { _ in scDone.fulfill() }
            sc.start()
            wait(for: [scDone], timeout: 5)
            sc.stop()

            let nmDone = expectation(description: "network monitor delivered snapshot")
            let nm = NetworkMonitor()
            nmBox.value = nm
            nm.onSnapshotUpdated = { _ in nmDone.fulfill() }
            nm.startMonitoring()
            wait(for: [nmDone], timeout: 5)
            nm.stopMonitoring()
        }

        autoreleasepool {
            runMonitorCycle()
        }

        // Allow any in-flight deliveryQueue work items to finish before checking weak references
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertNil(scBox.value, "SystemConfigurationMonitor should deallocate after stop")
        XCTAssertNil(nmBox.value, "NetworkMonitor should deallocate after stopMonitoring")
    }
}
