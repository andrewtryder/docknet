# DockNet

**DockNet** is a lightweight, event-driven native macOS menu-bar application built in Swift by **Andrew Ryder**.

It dynamically monitors configured physical wired Ethernet interfaces and Wi-Fi, tracking macOS Network Service Order and the authoritative system primary interface (`State:/Network/Global/IPv4`). DockNet provides clear status visibility and optional native notifications during network transitions, while keeping Wi-Fi associated as an immediate, zero-downtime fallback whenever Ethernet is disconnected, negotiating, or degraded.

<p align="center">
  <img src="assets/docknet-screenshot.png" alt="DockNet Live Menu Bar Interface" width="300">
</p>

**Author**: Andrew Ryder  
**Repository**: [https://github.com/andrewtryder/docknet](https://github.com/andrewtryder/docknet)

---

## Key Features

1. **Authoritative Primary Connection**:
   - Distinctly tracks and displays the actual macOS system primary interface (`State:/Network/Global/IPv4`), service order preference, and interface health.
   - Wi-Fi is clearly marked as `Connected · Primary` when active as the default route, and `Connected · Standby` when connected while Ethernet is primary.

2. **Configured Wired Services Discovery & Fine-Grained States**:
   - Shows only configured `SCNetworkService` Ethernet entries, filtering out dormant or unconfigured raw hardware adapters (`HiddenConfiguration == true`).
   - Accurately reports states: `Disabled`, `Adapter Not Present`, `Cable Disconnected`, `Obtaining DHCP`, `Degraded`, `Ready · Primary`, and `Ready · Available`.
   - Exposes negotiated link speed (e.g. `100 Mbps Full Duplex`, `1 Gbps Full Duplex`, `2.5 Gbps Full Duplex`) using Darwin's in-memory BSD `SIOCGIFMEDIA` socket ioctl without shell polling.

3. **Opt-In Native Transition Notifications**:
   - Controlled via the user preference checkbox: `Notify on connection changes`.
   - Requests macOS notification permission (`[.alert]`, sounds disabled by default) only when explicitly enabled by the user.
   - If notification authorization is denied by macOS, the UI clearly displays `⚠ Notifications disabled by macOS` with a shortcut to System Settings.
   - Notifies only on subsequent stable primary interface changes (Wi-Fi ↔ Ethernet, or switching between physical Ethernet adapters).
   - Quiet startup: no notification is emitted on application launch (`previousPrimary == nil`).
   - Debounced (1000 ms) and deduplicated to prevent flapping and banner spam.

4. **Polished Native About DockNet Window**:
   - Access via `About DockNet…` near the bottom of the menu bar.
   - Features the custom vector identity, dynamically read version/build (`Version 1.0 (1)`), creator attribution (**Created by Andrew Ryder**), and a direct link to the canonical GitHub repository.
   - Managed as a single native window that activates and fronts if selected again.

5. **Observational Architecture & Zero Route Manipulation**:
   - Operates entirely via event-driven kernel notifications (`SCDynamicStoreSetDispatchQueue` + `NWPathMonitor`).
   - Does **not** modify routing tables, does not disable Wi-Fi, does not force DHCP, does not require root, and installs no privileged helpers.

6. **Real macOS UI Automation with XCUITest**:
   - Automated UI testing target (`DockNetUITests`) testing the real running application.
   - Dedicated `--ui-testing` test presentation mode hosting the production SwiftUI `MenuBarView` with complete accessibility identifiers.
   - Deterministic test state injection and dynamic multi-state transition testing without restarting the application.
   - Non-destructive live hardware smoke test (`make test-ui-live`).
   - Automatic screenshot export to `build/screenshots/` and accessibility audit validation.

7. **Local Ad-hoc Signing**:
   - Configured with "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`).
   - Launch at Login managed via modern `SMAppService.mainApp` (macOS 13.0+).

---

## Make Targets & Commands

```bash
# Build Debug binary using Apple's canonical xcodebuild
make build

# Run unit tests (NetworkStateMachineTests)
make test-unit

# Run deterministic XCUITest UI automation suite (DockNetUITests)
make test-ui

# Run observational live network smoke test against real hardware (DockNetLiveUITests)
make test-ui-live

# Send a manual test notification using the installed application
make test-notification

# Run all test suites (unit + UI tests)
make test-all

# Install to ~/Applications/DockNet.app
make install

# Launch application
make run

# Stream live state transitions from running DockNet
make watch

# Run comprehensive read-only network diagnostics
make diagnose

# Clean local build and screenshot artifacts
make clean

# Regenerate DockNet.xcodeproj from project.yml (requires xcodegen)
make regenerate-project
```

---

## Test Automation & Screenshots

When running `make test-ui` or `make test-all`, screenshots for key network states are automatically captured and saved to `build/screenshots/`:
- `wifi_primary.png`: Wi-Fi active as primary connection
- `single_ethernet_primary.png`: Single wired Ethernet connected, healthy, and preferred
- `ethernet_degraded.png`: Degraded / self-assigned `169.254.x.x` link-local address
- `two_ethernet_adapters_one_healthy.png`: Multiple adapters with only one healthy
- `two_ethernet_both_ready.png`: Multiple ready adapters respecting service order precedence
- `live_hardware_network_state.png`: Real snapshot captured during live smoke testing
