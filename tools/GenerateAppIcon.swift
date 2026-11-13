import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("Assets/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2),
]

for spec in sizes {
    let pixels = spec.points * spec.scale
    let image = drawIcon(size: pixels)
    let fileURL = iconsetURL.appendingPathComponent(spec.name)
    try writePNG(image, to: fileURL)
}

func drawIcon(size pixels: Int) -> NSImage {
    let size = CGSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let canvas = CGRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    canvas.fill()

    let iconRect = canvas.insetBy(dx: CGFloat(pixels) * 0.075, dy: CGFloat(pixels) * 0.075)
    let radius = CGFloat(pixels) * 0.215
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -CGFloat(pixels) * 0.018),
        blur: CGFloat(pixels) * 0.045,
        color: NSColor.black.withAlphaComponent(0.34).cgColor
    )
    NSColor.black.setFill()
    iconPath.fill()
    context.restoreGState()

    iconPath.addClip()

    drawGradientBase(in: iconRect, context: context)
    drawBottomGlow(in: iconRect, context: context)
    drawTopGlow(in: iconRect, context: context)
    drawDiagonalWash(in: iconRect, context: context)
    drawWhiteMark(in: iconRect)
    drawInnerSheen(in: iconRect, context: context)

    return image
}

func drawGradientBase(in rect: CGRect, context: CGContext) {
    let colors = [
        NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.45, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.63, blue: 0.30, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.96, green: 0.16, blue: 0.62, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.07, green: 0.83, blue: 0.94, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.34, 0.67, 1.0])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
}

func drawTopGlow(in rect: CGRect, context: CGContext) {
    let colors = [
        NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.24, alpha: 0.78).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.18, alpha: 0.0).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    let center = CGPoint(x: rect.minX + rect.width * 0.44, y: rect.maxY + rect.height * 0.02)
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: rect.width * 0.54,
        options: [.drawsAfterEndLocation]
    )
}

func drawBottomGlow(in rect: CGRect, context: CGContext) {
    let colors = [
        NSColor(calibratedRed: 0.45, green: 0.08, blue: 0.98, alpha: 0.78).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.80, blue: 0.98, alpha: 0.72).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.80, blue: 0.98, alpha: 0.0).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.46, 1])!
    let center = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.08)
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: rect.width * 0.68,
        options: [.drawsAfterEndLocation]
    )
}

func drawDiagonalWash(in rect: CGRect, context: CGContext) {
    let colors = [
        NSColor.white.withAlphaComponent(0.26).cgColor,
        NSColor.white.withAlphaComponent(0.03).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.10),
        end: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.16),
        options: []
    )
}

func drawWhiteMark(in rect: CGRect) {
    let stemRect = CGRect(
        x: rect.minX + rect.width * 0.205,
        y: rect.minY + rect.height * 0.305,
        width: rect.width * 0.135,
        height: rect.height * 0.415
    )
    let stem = NSBezierPath(roundedRect: stemRect, xRadius: stemRect.width * 0.48, yRadius: stemRect.width * 0.48)
    NSColor.white.withAlphaComponent(0.94).setFill()
    stem.fill()

    let mark = NSBezierPath()
    mark.move(to: CGPoint(x: rect.minX + rect.width * 0.295, y: rect.minY + rect.height * 0.705))
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.295, y: rect.minY + rect.height * 0.525))
    mark.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.455, y: rect.minY + rect.height * 0.305),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.295, y: rect.minY + rect.height * 0.385),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.365, y: rect.minY + rect.height * 0.305)
    )
    mark.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.615, y: rect.minY + rect.height * 0.470),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.545, y: rect.minY + rect.height * 0.305),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.615, y: rect.minY + rect.height * 0.365)
    )
    mark.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.725, y: rect.minY + rect.height * 0.705),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.615, y: rect.minY + rect.height * 0.625),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.665, y: rect.minY + rect.height * 0.705)
    )
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.835, y: rect.minY + rect.height * 0.705))
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.835, y: rect.minY + rect.height * 0.315))
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.700, y: rect.minY + rect.height * 0.315))
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.700, y: rect.minY + rect.height * 0.455))
    mark.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.460, y: rect.minY + rect.height * 0.185),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.680, y: rect.minY + rect.height * 0.290),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.585, y: rect.minY + rect.height * 0.185)
    )
    mark.curve(
        to: CGPoint(x: rect.minX + rect.width * 0.165, y: rect.minY + rect.height * 0.525),
        controlPoint1: CGPoint(x: rect.minX + rect.width * 0.295, y: rect.minY + rect.height * 0.185),
        controlPoint2: CGPoint(x: rect.minX + rect.width * 0.165, y: rect.minY + rect.height * 0.330)
    )
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.165, y: rect.minY + rect.height * 0.705))
    mark.line(to: CGPoint(x: rect.minX + rect.width * 0.295, y: rect.minY + rect.height * 0.705))
    mark.close()
    NSColor.white.withAlphaComponent(0.94).setFill()
    mark.fill()
}

func drawInnerSheen(in rect: CGRect, context: CGContext) {
    context.saveGState()
    NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.018, dy: rect.height * 0.018), xRadius: rect.width * 0.20, yRadius: rect.width * 0.20).addClip()
    NSColor.white.withAlphaComponent(0.13).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.025, dy: rect.height * 0.025), xRadius: rect.width * 0.19, yRadius: rect.width * 0.19)
    border.lineWidth = rect.width * 0.018
    border.stroke()
    context.restoreGState()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}
