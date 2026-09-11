import AppKit

/// Lightweight native status indicator dot (7x7 pt).
/// Uses native AppKit NSBezierPath without emojis, unicode circle characters, or animations.
@MainActor
public final class StatusIndicatorView: NSView {
    public enum Tone {
        case green
        case gray
        case orange
        case red

        public var color: NSColor {
            switch self {
            case .green:
                return .systemGreen
            case .gray:
                return .secondaryLabelColor
            case .orange:
                return .systemOrange
            case .red:
                return .systemRed
            }
        }
    }

    public var tone: Tone = .gray {
        didSet {
            if oldValue != tone {
                needsDisplay = true
            }
        }
    }

    public init(tone: Tone = .gray) {
        self.tone = tone
        super.init(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 8, height: 8)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let circleRect = NSRect(x: 0.5, y: 0.5, width: 7, height: 7)
        let path = NSBezierPath(ovalIn: circleRect)
        tone.color.setFill()
        path.fill()
    }
}
