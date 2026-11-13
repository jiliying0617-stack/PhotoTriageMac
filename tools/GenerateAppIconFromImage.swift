import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: swift GenerateAppIconFromImage.swift <source-image>\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = URL(fileURLWithPath: args[1])
let iconsetURL = root.appendingPathComponent("Assets/AppIcon.iconset", isDirectory: true)

let sourceData = try Data(contentsOf: sourceURL)
guard let sourceRep = NSBitmapImageRep(data: sourceData),
      let sourceCGImage = sourceRep.cgImage else {
    fputs("Unable to read source image: \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let cropRect = squareCropRect(for: sourceRep, imageWidth: sourceCGImage.width, imageHeight: sourceCGImage.height)
guard let cropped = sourceCGImage.cropping(to: cropRect) else {
    fputs("Unable to crop source image\n", stderr)
    exit(1)
}

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
    let image = renderIcon(from: cropped, pixels: pixels)
    try writePNG(image, to: iconsetURL.appendingPathComponent(spec.name))
}

func squareCropRect(for bitmap: NSBitmapImageRep, imageWidth: Int, imageHeight: Int) -> CGRect {
    var minX = imageWidth
    var minY = imageHeight
    var maxX = 0
    var maxY = 0

    for y in 0..<imageHeight {
        for x in 0..<imageWidth {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let alpha = color.alphaComponent
            let isWhite = color.redComponent > 0.965 && color.greenComponent > 0.965 && color.blueComponent > 0.965
            if alpha > 0.05 && !isWhite {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX <= maxX, minY <= maxY else {
        let side = min(imageWidth, imageHeight)
        return CGRect(x: (imageWidth - side) / 2, y: (imageHeight - side) / 2, width: side, height: side)
    }

    let padding = Int(Double(max(maxX - minX + 1, maxY - minY + 1)) * 0.015)
    minX = max(minX - padding, 0)
    minY = max(minY - padding, 0)
    maxX = min(maxX + padding, imageWidth - 1)
    maxY = min(maxY + padding, imageHeight - 1)

    let width = maxX - minX + 1
    let height = maxY - minY + 1
    let side = min(max(width, height), min(imageWidth, imageHeight))
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    var originX = centerX - side / 2
    var originY = centerY - side / 2
    originX = min(max(originX, 0), imageWidth - side)
    originY = min(max(originY, 0), imageHeight - side)

    return CGRect(x: originX, y: originY, width: side, height: side)
}

func renderIcon(from image: CGImage, pixels: Int) -> NSImage {
    let output = NSImage(size: CGSize(width: pixels, height: pixels))
    output.lockFocus()
    defer { output.unlockFocus() }

    NSColor.clear.setFill()
    CGRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let nsImage = NSImage(cgImage: image, size: CGSize(width: pixels, height: pixels))
    nsImage.draw(
        in: CGRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    return output
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}
