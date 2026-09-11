import AppKit
import CoreGraphics
import Foundation

func createDockNetIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let scale = size / 1024.0

    // Standard macOS squircle dimensions inside 1024x1024 canvas
    let inset = 80.0 * scale
    let squircleRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let cornerRadius = 185.0 * scale
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Subtle drop shadow for squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12 * scale),
        blur: 24 * scale,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for interior rendering
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Rich dark gradient: Deep modern slate navy
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.16, green: 0.22, blue: 0.31, alpha: 1.0), // #29384F
        CGColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 1.0)  // #141C2B
    ] as CFArray

    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: size / 2, y: size - inset),
            end: CGPoint(x: size / 2, y: inset),
            options: []
        )
    }

    // Subtle radial highlight from top
    let highlightColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            highlightGrad,
            startCenter: CGPoint(x: size / 2, y: size - inset),
            startRadius: 0,
            endCenter: CGPoint(x: size / 2, y: size / 2),
            endRadius: squircleRect.width * 0.7,
            options: []
        )
    }

    // Draw emblem in crisp white / subtle cool silver
    let glyphScale = (squircleRect.width * 0.54) / 24.0
    let glyphCenterX = size / 2
    let glyphCenterY = size / 2 + 10 * scale

    // Shift to center glyph: 24x24 viewBox centered at (12, 12)
    ctx.saveGState()
    ctx.translateBy(x: glyphCenterX, y: glyphCenterY)
    ctx.scaleBy(x: glyphScale, y: -glyphScale)
    ctx.translateBy(x: -12.0, y: -12.0)

    let strokeColor = CGColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1.0)
    ctx.setStrokeColor(strokeColor)
    ctx.setFillColor(strokeColor)

    // 1. RJ45 Outer Shell
    let rj45Path = CGMutablePath()
    rj45Path.move(to: CGPoint(x: 6, y: 3.5))
    rj45Path.addLine(to: CGPoint(x: 18, y: 3.5))
    rj45Path.addLine(to: CGPoint(x: 18, y: 5))
    rj45Path.addLine(to: CGPoint(x: 20, y: 5))
    rj45Path.addLine(to: CGPoint(x: 20, y: 10.5))
    rj45Path.addLine(to: CGPoint(x: 17.5, y: 10.5))
    rj45Path.addLine(to: CGPoint(x: 17.5, y: 12.5))
    rj45Path.addLine(to: CGPoint(x: 6.5, y: 12.5))
    rj45Path.addLine(to: CGPoint(x: 6.5, y: 10.5))
    rj45Path.addLine(to: CGPoint(x: 4, y: 10.5))
    rj45Path.addLine(to: CGPoint(x: 4, y: 5))
    rj45Path.addLine(to: CGPoint(x: 6, y: 5))
    rj45Path.closeSubpath()

    ctx.setLineWidth(2.0)
    ctx.setLineJoin(.round)
    ctx.addPath(rj45Path)
    ctx.strokePath()

    // 2. RJ45 Connector Pins
    let pinsPath = CGMutablePath()
    pinsPath.move(to: CGPoint(x: 8, y: 4.2))
    pinsPath.addLine(to: CGPoint(x: 8, y: 7))
    pinsPath.move(to: CGPoint(x: 10.7, y: 4.2))
    pinsPath.addLine(to: CGPoint(x: 10.7, y: 7))
    pinsPath.move(to: CGPoint(x: 13.3, y: 4.2))
    pinsPath.addLine(to: CGPoint(x: 13.3, y: 7))
    pinsPath.move(to: CGPoint(x: 16, y: 4.2))
    pinsPath.addLine(to: CGPoint(x: 16, y: 7))

    ctx.setLineWidth(1.4)
    ctx.setLineCap(.round)
    ctx.addPath(pinsPath)
    ctx.strokePath()

    // 3. Outer Wi-Fi Arc
    let wifiOuter = CGMutablePath()
    wifiOuter.move(to: CGPoint(x: 6.5, y: 15.5))
    wifiOuter.addCurve(to: CGPoint(x: 17.5, y: 15.5), control1: CGPoint(x: 9.7, y: 12.9), control2: CGPoint(x: 14.3, y: 12.9))
    ctx.setLineWidth(2.0)
    ctx.setLineCap(.round)
    ctx.addPath(wifiOuter)
    ctx.strokePath()

    // 4. Inner Wi-Fi Arc
    let wifiInner = CGMutablePath()
    wifiInner.move(to: CGPoint(x: 9, y: 18))
    wifiInner.addCurve(to: CGPoint(x: 15, y: 18), control1: CGPoint(x: 10.7, y: 16.6), control2: CGPoint(x: 13.3, y: 16.6))
    ctx.setLineWidth(2.0)
    ctx.setLineCap(.round)
    ctx.addPath(wifiInner)
    ctx.strokePath()

    // 5. Wi-Fi Dot
    let dotRect = CGRect(x: 12 - 1.2, y: 20.5 - 1.2, width: 2.4, height: 2.4)
    ctx.fillEllipse(in: dotRect)

    ctx.restoreGState() // restore glyph transform
    ctx.restoreGState() // restore squircle clip

    // Subtle squircle inner stroke
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(1.5 * scale)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16))
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to convert image to PNG for \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let appIconSetDir = "DockNet/Assets.xcassets/AppIcon.appiconset"
let iconSetDir = "/tmp/AppIcon.iconset"

try? fm.createDirectory(atPath: appIconSetDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: iconSetDir, withIntermediateDirectories: true)

// List of required macOS icon pixel sizes
let iconSizes: [(name: String, pixelSize: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in iconSizes {
    let img = createDockNetIcon(size: CGFloat(item.pixelSize))
    let xcPath = "\(appIconSetDir)/\(item.name)"
    let icnsPath = "\(iconSetDir)/\(item.name)"
    savePNG(image: img, to: xcPath)
    savePNG(image: img, to: icnsPath)
    print("Generated \(item.name) (\(item.pixelSize)x\(item.pixelSize))")
}

// Write Contents.json for AppIcon.appiconset
let contentsJSON = """
{
  "images" : [
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16.png",
      "scale" : "1x"
    },
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32.png",
      "scale" : "1x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128.png",
      "scale" : "1x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256.png",
      "scale" : "1x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512.png",
      "scale" : "1x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512@2x.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

try? contentsJSON.write(toFile: "\(appIconSetDir)/Contents.json", atomically: true, encoding: .utf8)
print("Wrote \(appIconSetDir)/Contents.json")
