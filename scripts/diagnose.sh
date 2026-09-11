#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo " DockNet Comprehensive Diagnostic Report"
echo " Date: $(date)"
echo " Host: $(hostname)"
echo "============================================================"

echo ""
echo "--- 1. Configured Network Services & Service Order ---"
networksetup -listnetworkserviceorder || true

echo ""
echo "--- 2. Discovered Hardware Ports ---"
networksetup -listallhardwareports || true

echo ""
echo "--- 3. SystemConfiguration Network Services & BSD Interfaces ---"
swift -e '
import Foundation
import SystemConfiguration

guard let prefs = SCPreferencesCreate(nil, "DockNetDiagnose" as CFString, nil),
      let currentSet = SCNetworkSetCopyCurrent(prefs) else {
    print("Could not access SystemConfiguration network set")
    exit(0)
}

let serviceOrder = (SCNetworkSetGetServiceOrder(currentSet) as? [String]) ?? []
guard let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
    print("Could not copy services")
    exit(0)
}

print("Configured Network Services in macOS Priority Order:")
for (idx, sid) in serviceOrder.enumerated() {
    guard let s = services.first(where: { (SCNetworkServiceGetServiceID($0) as String?) == sid }) else { continue }
    let name = (SCNetworkServiceGetName(s) as String?) ?? "Unknown"
    let enabled = SCNetworkServiceGetEnabled(s)
    let iface = SCNetworkServiceGetInterface(s)
    let bsd = iface.flatMap { SCNetworkInterfaceGetBSDName($0) as String? } ?? "none"
    let type = iface.flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? } ?? "none"
    let statusStr = enabled ? "ENABLED " : "DISABLED"
    print("  [\(idx + 1)] \(statusStr) | BSD: \(bsd.padding(toLength: 7, withPad: " ", startingAt: 0)) | Type: \(type.padding(toLength: 10, withPad: " ", startingAt: 0)) | Service: \(name) (\(sid))")
}
' || true

echo ""
echo "--- 4. Active Interface Status & IP Details ---"
for iface in $(ifconfig -l); do
    # Only report Ethernet (en*) or bridge/tunnel
    if [[ "$iface" =~ ^en[0-9]+$ ]]; then
        status=$(ifconfig "$iface" 2>/dev/null | grep "status:" | awk '{print $2}' || echo "unknown")
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "None")
        echo "Interface $iface: status=$status, IPv4=$ip"
    fi
done

echo ""
echo "--- 5. Current Default Route ---"
route -n get default || echo "No default route found"

echo ""
echo "--- 6. Authoritative SCDynamicStore Global IPv4 State ---"
scutil <<EOF || true
show State:/Network/Global/IPv4
quit
EOF

echo ""
echo "--- 7. Network Information (scutil --nwi) ---"
scutil --nwi || true

echo ""
echo "============================================================"
echo " End of Diagnostic Report"
echo "============================================================"
