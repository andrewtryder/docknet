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
echo "--- 6. Primary Connection Resolution ---"
swift -e '
import Foundation
import SystemConfiguration

guard let store = SCDynamicStoreCreate(nil, "DockNetDiagnose" as CFString, nil, nil) else {
    print("Could not access SCDynamicStore")
    exit(0)
}

var systemPrimary = "none"
if let globalDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
   let p = globalDict["PrimaryInterface"] as? String {
    systemPrimary = p
}

// Find physical primary
var physicalPrimary = "none"
for iface in ["en6", "en8", "en9", "en5", "en4", "en7"] {
    if let linkDict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(iface)/Link" as CFString) as? [String: Any],
       let active = linkDict["Active"] as? Bool, active,
       let ipDict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(iface)/IPv4" as CFString) as? [String: Any],
       let addrs = ipDict["Addresses"] as? [String], !addrs.isEmpty, !addrs[0].hasPrefix("169.254.") {
        physicalPrimary = iface
        break
    }
}
if physicalPrimary == "none" {
    if let linkDict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/en0/Link" as CFString) as? [String: Any],
       let active = linkDict["Active"] as? Bool, active {
        physicalPrimary = "en0"
    }
}

print("DockNet Physical Primary: \(physicalPrimary)")
print("macOS System Primary:     \(systemPrimary)")
' || true

echo ""
echo "--- 7. Virtual & Overlay Interfaces (Diagnostic Only) ---"
for iface in $(ifconfig -l); do
    if [[ "$iface" =~ ^(utun|ipsec|ppp|gif|stf|bridge)[0-9]+$ ]]; then
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null || ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}' || echo "No IP")
        echo "Virtual/Tunnel Interface $iface: IPv4=$ip"
    fi
done

echo ""
echo "--- 8. Authoritative SCDynamicStore Global IPv4 State ---"
scutil <<EOF || true
show State:/Network/Global/IPv4
quit
EOF

echo ""
echo "--- 9. Network Information (scutil --nwi) ---"
scutil --nwi || true

echo ""
echo "============================================================"
echo " End of Diagnostic Report"
echo "============================================================"
