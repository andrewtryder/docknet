import Foundation
import Darwin

/// Protocol for detecting negotiated Ethernet link speed.
public protocol LinkSpeedDetecting: Sendable {
    func detectLinkSpeed(for bsdName: String) -> String?
}

/// Native macOS link speed detector using in-memory BSD socket ioctl (`SIOCGIFMEDIA`).
/// Does not invoke shell processes, `ifconfig`, or periodic polling.
public struct LinkSpeedDetector: LinkSpeedDetecting {
    public init() {}

    public func detectLinkSpeed(for bsdName: String) -> String? {
        guard !bsdName.isEmpty, if_nametoindex(bsdName) > 0 else {
            return nil
        }

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var ifmr = ifmediareq()
        withUnsafeMutableBytes(of: &ifmr.ifm_name) { ptr in
            let bytes = bsdName.utf8
            let copyLen = min(bytes.count, 15) // IFNAMSIZ - 1
            ptr.copyBytes(from: bytes.prefix(copyLen))
        }

        let SIOCGIFMEDIA: UInt = 0xc02c6938
        guard ioctl(sock, SIOCGIFMEDIA, &ifmr) == 0 else {
            return nil
        }

        let active = ifmr.ifm_active
        let ifmType = active & 0x00000380
        guard ifmType == 0x00000020 else { // IFM_ETHER
            return nil
        }

        let subtype = active & 0x0000007f
        let speedString: String?
        switch subtype {
        case 3, 4, 5, 12, 13:
            speedString = "10 Mbps"
        case 6, 7, 8, 9, 10, 52:
            speedString = "100 Mbps"
        case 11, 14, 15, 16, 24, 25, 41:
            speedString = "1 Gbps"
        case 22, 32, 36, 63:
            speedString = "2.5 Gbps"
        case 23, 64, 69, 70:
            speedString = "5 Gbps"
        case 17, 18, 19, 20, 21, 26, 27, 28, 29, 33, 34, 35, 42:
            speedString = "10 Gbps"
        default:
            speedString = nil
        }

        guard let speed = speedString else { return nil }

        let isFullDuplex = (active & 0x00100000) != 0 // IFM_FDX
        let duplex = isFullDuplex ? "Full Duplex" : "Half Duplex"

        return "\(speed) \(duplex)"
    }
}
