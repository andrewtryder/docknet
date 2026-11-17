# Engineering audit notes

DockNet observes system state; it does not alter network configuration or test Internet reachability. The system primary is read from the IPv4 global state, falling back to IPv6 when IPv4 has no primary. When an overlay hides the physical route, the physical transport is inferred from enabled services, health, service order and the previous physical transport. This inference is not an OS-confirmed route.

A valid IPv4 address without a gateway is reported as configured, not as a DHCP lease in progress or proof of Internet connectivity. A system-selected Ethernet interface can be primary even when its IPv4 state is not gateway-ready. IPv6-only route selection is observed, but DockNet does not currently show IPv6 addresses or evaluate IPv6 address health.

## Remaining verification

- **Medium:** Exercise actual sleep/wake, dock reconnect, simultaneous adapters, static and IPv6-only networks, and VPN route changes on physical hardware. Unit and deterministic UI tests cannot reproduce all SystemConfiguration timing or device drivers.
- **Medium:** Test 2.5/5/10 Gbps and unsupported `SIOCGIFMEDIA` adapters on hardware; media constants are checked against the SDK and exercised as pure media words.
- **Low:** SwiftLint still reports existing nonfatal maintainability and naming warnings. Formatting is owned by SwiftFormat; default function-length error limits are enabled.
- **Low:** The release is ad-hoc signed and not notarized. A notification already submitted to macOS cannot be withdrawn by a subsequent state change; pending authorization and debounce work is invalidated before submission. A snapshot callback already in progress can finish after stop; queued callbacks from a stopped monitor generation are discarded.

## Optional product ideas

A last-change timestamp or bounded history is inexpensive but needs persistence and clear semantics for inferred transitions; defer until users need it. Link-speed notifications require hardware verification and debounce rules, so defer. Copy Diagnostics requires a deliberate privacy review and redaction of interface names and addresses; defer. An inferred-route indicator is testable and low overhead, but requires a product decision about presentation; the model already retains the observed system primary separately from the resolved physical transport. None of these warrants polling or privileged access.
