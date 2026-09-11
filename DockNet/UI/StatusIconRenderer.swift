import AppKit

public enum StatusIconState: Hashable, Sendable {
    case wifiPrimary
    case ethernetPrimary
    case ethernetNegotiating
    case ethernetDegraded
    case offline

    public var accessibilityLabel: String {
        switch self {
        case .wifiPrimary:
            return "DockNet — Wi-Fi primary"
        case .ethernetPrimary:
            return "DockNet — Ethernet primary"
        case .ethernetNegotiating:
            return "DockNet — Ethernet negotiating"
        case .ethernetDegraded:
            return "DockNet — Ethernet degraded"
        case .offline:
            return "DockNet — Disconnected"
        }
    }

    public static func from(snapshot: NetworkSnapshot) -> StatusIconState {
        let isEthernetNegotiating = snapshot.wiredInterfaces.contains(where: {
            $0.health == .obtainingDHCP || $0.health == .linkUp
        })
        let isEthernetDegraded = snapshot.wiredInterfaces.contains(where: {
            $0.health == .degraded
        })

        if snapshot.actualPrimaryIsWired {
            if isEthernetDegraded {
                return .ethernetDegraded
            }
            return .ethernetPrimary
        }

        if isEthernetNegotiating {
            return .ethernetNegotiating
        }

        if isEthernetDegraded {
            return .ethernetDegraded
        }

        if snapshot.isWifiPrimary {
            return .wifiPrimary
        }

        return .offline
    }
}

public final class StatusIconRenderer: @unchecked Sendable {
    private static let lock = NSLock()
    private static var imageCache: [StatusIconState: NSImage] = [:]

    public static func image(for state: StatusIconState) -> NSImage {
        lock.lock()
        defer { lock.unlock() }

        if let cached = imageCache[state] {
            return cached
        }

        let rendered = render(state: state)
        imageCache[state] = rendered
        return rendered
    }

    private static func render(state: StatusIconState) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let ethColor: NSColor
        let wifiColor: NSColor
        let showNegotiatingDots: Bool
        let showDegradedBadge: Bool

        switch state {
        case .ethernetPrimary:
            ethColor = .systemGreen
            wifiColor = .secondaryLabelColor
            showNegotiatingDots = false
            showDegradedBadge = false

        case .ethernetNegotiating:
            ethColor = .systemOrange
            wifiColor = .secondaryLabelColor
            showNegotiatingDots = true
            showDegradedBadge = false

        case .ethernetDegraded:
            ethColor = .systemOrange
            wifiColor = .secondaryLabelColor
            showNegotiatingDots = false
            showDegradedBadge = true

        case .wifiPrimary:
            ethColor = .secondaryLabelColor
            wifiColor = .systemGreen
            showNegotiatingDots = false
            showDegradedBadge = false

        case .offline:
            ethColor = .secondaryLabelColor
            wifiColor = .secondaryLabelColor
            showNegotiatingDots = false
            showDegradedBadge = false
        }

        let ethGlyph = NSImage(named: "DockNetEthernetGlyph")
        let wifiGlyph = NSImage(named: "DockNetWiFiGlyph")

        let image = NSImage(size: size, flipped: false) { rect in
            if let eth = ethGlyph {
                drawTinted(glyph: eth, color: ethColor, in: rect)
            }
            if let wifi = wifiGlyph {
                drawTinted(glyph: wifi, color: wifiColor, in: rect)
            }

            if showNegotiatingDots {
                NSColor.systemOrange.setFill()
                let dotY: CGFloat = 2
                let dotSize: CGFloat = 2
                NSRect(x: 10, y: dotY, width: dotSize, height: dotSize).fill()
                NSRect(x: 13, y: dotY, width: dotSize, height: dotSize).fill()
                NSRect(x: 16, y: dotY, width: dotSize, height: dotSize).fill()
            } else if showDegradedBadge {
                NSColor.systemRed.setFill()
                let circleRect = NSRect(x: 11, y: 1, width: 6, height: 6)
                let path = NSBezierPath(ovalIn: circleRect)
                path.fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private static func drawTinted(glyph: NSImage, color: NSColor, in rect: NSRect) {
        guard let cgContext = NSGraphicsContext.current?.cgContext,
              let cgImage = glyph.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        cgContext.saveGState()
        cgContext.clip(to: rect, mask: cgImage)
        color.setFill()
        rect.fill()
        cgContext.restoreGState()
    }
}
