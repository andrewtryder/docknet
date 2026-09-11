import Foundation
import Darwin

/// Protocol for detecting negotiated Ethernet link speed.
public protocol LinkSpeedDetecting: Sendable {
    func detectLinkSpeed(for bsdName: String) -> String?
}

/// Compatibility constants and subtype definitions mirroring Darwin's `<net/if_media.h>`.
/// These are isolated here because Swift's C importer does not expand Darwin's complex
/// macro definitions like `_IOWR('i', 56, struct ifmediareq)`.
public enum DarwinIfMediaCompatibility {
    /// `_IOWR('i', 56, struct ifmediareq)` ioctl command on 64-bit Darwin macOS.
    public static let SIOCGIFMEDIA: UInt = 0xc02c6938

    /// `IFM_TYPE_MASK` (`IFM_NMASK`): mask for media type (bits 5-7).
    public static let IFM_TYPE_MASK: Int32 = 0x000000e0
    /// `IFM_ETHER`: Ethernet media type.
    public static let IFM_ETHER: Int32 = 0x00000020
    /// `IFM_SUBTYPE_MASK` (`IFM_TMASK`): mask for media subtype.
    public static let IFM_SUBTYPE_MASK: Int32 = 0x000f001f
    /// `IFM_FDX`: Full duplex flag (bit 20).
    public static let IFM_FDX: Int32 = 0x00100000
}

/// Native macOS link speed detector using in-memory BSD socket ioctl (`SIOCGIFMEDIA`).
/// Does not invoke shell processes, `ifconfig`, `networksetup`, or periodic polling.
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

        guard ioctl(sock, DarwinIfMediaCompatibility.SIOCGIFMEDIA, &ifmr) == 0 else {
            return nil
        }

        return Self.formatLinkSpeed(activeWord: ifmr.ifm_active)
    }

    /// Pure formatting function translating a Darwin `ifmr.ifm_active` media word
    /// into a human-readable link speed string (e.g. "1 Gbps Full Duplex").
    public static func formatLinkSpeed(activeWord: Int32) -> String? {
        let ifmType = activeWord & DarwinIfMediaCompatibility.IFM_TYPE_MASK
        guard ifmType == DarwinIfMediaCompatibility.IFM_ETHER else {
            return nil
        }

        let subtype = activeWord & DarwinIfMediaCompatibility.IFM_SUBTYPE_MASK
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

        let isFullDuplex = (activeWord & DarwinIfMediaCompatibility.IFM_FDX) != 0
        let duplex = isFullDuplex ? "Full Duplex" : "Half Duplex"

        return "\(speed) \(duplex)"
    }
}
