import Darwin
import Foundation

/// Protocol for detecting negotiated Ethernet link speed.
public protocol LinkSpeedDetecting: Sendable {
    func detectLinkSpeed(for bsdName: String) -> String?
}

/// Compatibility constants and subtype definitions mirroring Darwin's `<net/if_media.h>`.
/// These are isolated here because Swift's C importer does not expand Darwin's complex
/// macro definitions like `_IOWR('i', 56, struct ifmediareq)`.
public enum DarwinIfMediaCompatibility {
    /// `_IOWR('i', 56, struct ifmediareq)` ioctl command on 64-bit Darwin macOS.
    public static let SIOCGIFMEDIA: UInt = 0xC02C_6938

    /// `IFM_TYPE_MASK` (`IFM_NMASK`): mask for media type (bits 5-7).
    public static let typeMask: Int32 = 0x0000_00E0
    /// `IFM_ETHER`: Ethernet media type.
    public static let ethernet: Int32 = 0x0000_0020
    /// `IFM_SUBTYPE_MASK` (`IFM_TMASK`): mask for media subtype.
    public static let subtypeMask: Int32 = 0x000F_001F
    /// `IFM_FDX`: Full duplex flag (bit 20).
    public static let fullDuplex: Int32 = 0x0010_0000
}

/// Values are the decoded subtype numbers in <net/if_media.h>; values at or
/// above 32 use IFM_X_SUBTYPE's extended-bit encoding in a media word.
private enum EthernetMediaSubtype: Int32 {
    case base10T = 3, base10Two = 4, base10Five = 5
    case base100TX = 6, base100FX = 7, base100T4 = 8, base100VG = 9, base100T2 = 10
    case base1000SX = 11, base10STP = 12, base10FL = 13
    case base1000LX = 14, base1000CX = 15, base1000T = 16
    case base10GSR = 18, base10GLR = 19, base10GCX4 = 20, base10GT = 21
    case base2500T = 22, base5000T = 23, base1000CXSGMII = 24, base1000KX = 25
    case base10GKX4 = 26, base10GKR = 27, base10GCR1 = 28, base10GER = 29
    case base2500SX = 32, base10GTwinax = 33, base10GTwinaxLong = 34, base10GLRM = 35
    case base2500KX = 36, base1000SGMII = 41, base10GSFI = 42, base100T = 52
    case base10GAOC = 59, base100SGMII = 62, base2500X = 63
    case base5000KR = 64, base5000KRS = 69, base5000KR1 = 70
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
        let ifmType = activeWord & DarwinIfMediaCompatibility.typeMask
        guard ifmType == DarwinIfMediaCompatibility.ethernet else {
            return nil
        }

        // Decode IFM_X_SUBTYPE from the SDK: extended bits occupy bits 16...19.
        let subtype = (activeWord & 0x1F) | ((activeWord & 0x000F_0000) >> 11)
        let speedString: String?
        switch EthernetMediaSubtype(rawValue: subtype) {
        case .base10T, .base10Two, .base10Five, .base10STP, .base10FL:
            speedString = "10 Mbps"
        case .base100TX, .base100FX, .base100T4, .base100VG, .base100T2, .base100T, .base100SGMII:
            speedString = "100 Mbps"
        case .base1000SX, .base1000LX, .base1000CX, .base1000T, .base1000CXSGMII, .base1000KX, .base1000SGMII:
            speedString = "1 Gbps"
        case .base2500T, .base2500SX, .base2500KX, .base2500X:
            speedString = "2.5 Gbps"
        case .base5000T, .base5000KR, .base5000KRS, .base5000KR1:
            speedString = "5 Gbps"
        case .base10GSR, .base10GLR, .base10GCX4, .base10GT, .base10GKX4, .base10GKR, .base10GCR1,
             .base10GER, .base10GTwinax, .base10GTwinaxLong, .base10GLRM, .base10GSFI, .base10GAOC:
            speedString = "10 Gbps"
        case nil:
            speedString = nil
        }

        guard let speed = speedString else { return nil }

        let isFullDuplex = (activeWord & DarwinIfMediaCompatibility.fullDuplex) != 0
        let duplex = isFullDuplex ? "Full Duplex" : "Half Duplex"

        return "\(speed) \(duplex)"
    }
}
