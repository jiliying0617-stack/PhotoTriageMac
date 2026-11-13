import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

enum AssetMetadataReader {
    static func metadata(for fileURL: URL) -> AssetMetadata? {
#if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            return nil
        }

        if shouldSwapDimensions(for: properties[kCGImagePropertyOrientation]) {
            return AssetMetadata(width: height, height: width)
        }

        return AssetMetadata(width: width, height: height)
#else
        _ = fileURL
        return nil
#endif
    }

#if canImport(ImageIO)
    private static func shouldSwapDimensions(for orientationValue: Any?) -> Bool {
        let orientation: Int?
        if let number = orientationValue as? NSNumber {
            orientation = number.intValue
        } else {
            orientation = orientationValue as? Int
        }

        guard let orientation else { return false }
        return (5...8).contains(orientation)
    }
#endif
}
