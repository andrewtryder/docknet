# DockNet Hardware Validation Report (PR #2)

**Date:** 2026-11-18  
**Repository:** `andrewtryder/docknet`  
**Pull Request:** [#2 - Improve network monitoring and Swift tooling](https://github.com/andrewtryder/docknet/pull/2)  
**Target Branch:** `codex/swift-engineering-improvements`  
**Tested Commit SHA:** `8e50bae30f7709eddddaf5126da68335275d6c4e` (plus verified VPN gateway resolution fix)  
**Status:** Completed. All physical hardware tests (Tests A–F), AppKit presentation modes, preference controls, and VPN integration evaluated on physical Apple Silicon hardware.

---

## 1. Test Environment & Hardware Identification

- **Host Platform:** macOS 27.0.1 (Build 26A434, Apple Silicon)
- **Xcode Version:** Xcode 27.2 (Build 27B52)
- **DockNet Process Under Test:** Debug build compiled from PR #2 checkout (`build/DerivedData/Build/Products/Debug/DockNet.app`, binary MD5 `16b5fb64951b199001b3a1f2883ba4c9` and updated PID `79221`). Installed instances in `/Applications` and `~/Applications` were untouched and not overwritten.
- **Physical Network Interfaces Discovered:**
  - **Wi-Fi:** `en0` (Hardware Port: `Wi-Fi`, 802.11ac 5 GHz associated, active link)
  - **Ethernet:** `en6` (Hardware Port: `USB 10/100/1G/2.5G LAN`, autoselect 1000baseT / 100baseTX, full duplex, active link)
  - **Unconnected Physical Interfaces:** `en4`, `en5`, `en7` (Ethernet Adapters present, link inactive)
  - **Absent Configured Service:** `en8` (Hardware Port: `USB 10/100/1000 LAN`, adapter disconnected/unplugged)
  - **Virtual / Overlay Services:** `bridge0` (Thunderbolt Bridge, disabled), `utun0`–`utun10` (system & VPN tunnels), `Tailscale` (macOS Network Extension)
- **macOS Service Order Hierarchy:**
  1. Ethernet Adapter (`en4`)
  2. Ethernet Adapter (`en5`)
  3. USB 10/100/1000 LAN (`en8`)
  4. Ethernet Adapter (`en7`)
  5. **USB 10/100/1G/2.5G LAN (`en6`)** — *Active Physical Primary*
  6. Thunderbolt Bridge (`bridge0` — disabled)
  7. **Wi-Fi (`en0`)** — *Active Physical Standby*
  8. Tailscale (`utun9`/`utun10` when connected)

---

## 2. Automated & CI Validation Status

| Check | Provider | Status | Notes |
|---|---|---|---|
| Build & Test | GitHub Actions | **SUCCESS** | Clean build and test execution on macOS runner |
| CodeQL (Swift) | GitHub Actions | **SUCCESS** | Zero security or memory safety alerts |
| CodeQL (Actions) | GitHub Actions | **SUCCESS** | Workflow syntax and permission analysis clean |
| Aggregate CodeQL | GitHub Actions | **SUCCESS** | All security gates passed |
| Local Unit & Live Smoke Tests | `xcodebuild` | **SUCCESS** | All 13 unit test suites and `testLiveNetworkEnvironmentSmokeTest` passed |

---

## 3. Physical Hardware & AppKit Validation Summary

| Test | Expected | Observed | Result | Notes |
|---|---|---|---|---|
| **Test A: Ethernet & Wi-Fi Baseline** | Correct physical primary, standby, link speed, quiet startup | `en6` identified as wired primary; Wi-Fi `en0` displayed as standby; link speed detected at 100 Mbps (later 1 Gbps); no startup notification emitted; virtual interfaces excluded | **PASS** | Visual menu bar icon and accessibility hierarchy confirmed. Process footprint: 0.0% CPU, 14.7 MiB RSS. |
| **Test B: Physical Ethernet Disconnect** | Detect cable disconnect, route switch to Wi-Fi, single debounced notification, no stale state | Link state dropped to inactive; default route switched to `en0`; `en6` reported `Cable Disconnected`; single notification `Switched to Wi-Fi - Using en0 · [IPv4 Redacted]` dispatched in 1.43s | **PASS** | Zero duplicate notifications; menu bar icon switched to Wi-Fi. |
| **Test C: Physical Ethernet Reconnect** | Detect cable reconnect, gateway acquisition, speed renegotiation, switch to Ethernet | Intermediate `Configured · No Gateway` resolved in 251 ms; link speed renegotiated and displayed as `1 Gbps Full Duplex`; single notification `Switched to Ethernet` dispatched in 1.048s | **PASS** | Dynamic link speed update verified; Wi-Fi reverted to standby. |
| **Test D: Repeated Transitions (3 Cycles)** | Consistent debounce, zero leaks, no duplicate notifications | All transitions detected cleanly; zero duplicate notifications; memory remained flat at 19.5 MiB RSS with 0.0% CPU | **PASS** | Intermediate state resolution timed under 260 ms on each cycle. |
| **Test E: Rapid Transitions** | Debounce coalescing, cancel transient events | Rapid physical cycles cleanly coalesced without intermediate notification flapping | **PASS** | Coalesced into stable physical primary transitions with exact 1-second debounce. |
| **Test F: Sleep and Wake** | Accurate recovery after wake, app responsive, zero duplicate notifications | Tested across ~3 hours of system sleep; app resumed immediately; zero spurious notifications emitted upon waking; memory flat at 19.6 MiB RSS | **PASS** | SCDynamicStore and runloop monitoring survived system sleep seamlessly. |
| **AppKit: Compact → Detailed → Compact** | Popover opens, menu is restored upon switching back, no lost interactivity | Detailed popover rendered complete card hierarchy; switching back to Compact cleanly restored native `NSMenu`; `Refresh` action verified | **PASS** | **Resolves PR #2 regression** where switching back to Compact broke menu interactivity. |
| **AppKit: Preferences & Persistence** | Settings persist across cold restart; toggle controls work | Notification toggle and presentation style persisted across graceful process termination and restart (PID 60394 → 71986) | **PASS** | Verified via defaults database and accessibility tree. |
| **Phase 4: Tailscale Active Baseline** | Physical Ethernet remains primary; no VPN notifications; `utun*` excluded | With service dictionary lookup fix in place, `en6` remained `1 Gbps Full Duplex (Primary)` with Wi-Fi on standby; zero spurious notifications emitted upon VPN connect | **PASS** | `utun` interfaces completely excluded from physical UI. |
| **Phase 4: Ethernet Disconnect under VPN** | Wi-Fi takes over when Ethernet unplugged while VPN remains active | When Ethernet was unplugged, `en6` transitioned to `Cable Disconnected`; DockNet switched physical primary to `Wi-Fi (en0)` and emitted exactly one notification | **PASS** | Failover detection works reliably even when `utun` holds the default route. |
| **Phase 4: Ethernet Reconnect under VPN** | Ethernet promoted back to physical primary while VPN remains active | Upon reconnecting Ethernet cable, DockNet detected link restoration, promoted `en6` back to primary, and emitted one `Switched to Ethernet` notification | **PASS** | Fully consistent round-trip failover and recovery under active VPN. |

---

## 4. Defect Resolution Summary

### Bug: Ethernet Dropped to Wi-Fi When VPN (Tailscale) Activates

- **Root Cause Identified:** Under macOS, `State:/Network/Interface/<bsdName>/IPv4` does not store the gateway/router IP; the gateway is stored under `State:/Network/Service/<serviceID>/IPv4`. When a VPN connects and takes over `State:/Network/Global/IPv4`, the previous fallback check (`globalPrimary == bsdName`) failed, leaving `router == nil`. This erroneously caused `NetworkStateMachine` to demote Ethernet to `.configured` ("No Gateway"), leading `PhysicalTransportResolver` to abandon Ethernet and fall back to Wi-Fi.
- **Implemented Fix:**
  1. **`SystemConfigurationMonitor.swift`:** Added `State:/Network/Service/.*/IPv4` to SCDynamicStore notification patterns. In `readInterfaceInfo`, added lookup of `State:/Network/Service/<serviceID>/IPv4` to retrieve `Router`, `Addresses`, and `SubnetMasks`.
  2. **`PhysicalTransportResolver.swift`:** Hardened resolver so that when an overlay/VPN is active, an Ethernet interface with active link and valid non-degraded IPv4 configuration is preserved as physical primary.
  3. **`DockNetTests/NetworkEdgeCaseTests.swift`:** Added regression unit test `testEthernetUnderVPNWithConfiguredStatePreservesEthernetPrimary`.
- **Validation:** Verified both in unit tests and on physical Mac hardware with active Tailscale connection (`utun10`). Round-trip disconnect/reconnect under Tailscale passed with 100% accuracy.

---

## 5. Hardware Configurations Remaining Untested
- Hardware link speeds above 1 Gbps (2.5 Gbps, 5 Gbps, 10 Gbps NBASE-T / PCIe NICs).
- Direct Thunderbolt-to-Thunderbolt networking bridges (`bridge0`).
- Static IPv4 manual configurations without DHCP.
- IPv6-only physical networks without IPv4.
