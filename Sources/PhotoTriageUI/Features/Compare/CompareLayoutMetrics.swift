import SwiftUI

struct CompareWheelZoomEvent: Equatable {
    let deltaY: CGFloat
    let location: CGPoint
}

struct CompareZoomRequest: Equatable {
    let deltaY: CGFloat
    let anchor: CGPoint
    let containerSize: CGSize
    let viewport: CGSize
    let imageSize: CGSize
}

struct CompareOverlayLayerVisibility: Equatable {
    let persistentOverlayIsVisible: Bool
    let cyclicOverlayIsVisible: Bool
}

enum CompareCyclicOverlayBehavior {
    static func shouldApplyStateChange(
        currentValue: Bool,
        requestedValue: Bool,
        assetCount: Int
    ) -> Bool {
        assetCount >= 2 && currentValue != requestedValue
    }

    static func layerVisibility(isActive: Bool) -> CompareOverlayLayerVisibility {
        CompareOverlayLayerVisibility(
            persistentOverlayIsVisible: !isActive,
            cyclicOverlayIsVisible: isActive
        )
    }
}

enum CompareLayoutMetrics {
    static let overlayOpacity: CGFloat = 1
    static let toleranceResizeHandleHeight: CGFloat = 9

    static func compareWindowDefaultSize() -> CGSize {
        CGSize(width: 1500, height: 940)
    }

    static func compareWindowMinimumSize() -> CGSize {
        CGSize(width: 1180, height: 760)
    }

    static func overviewPaneWidth(containerWidth: CGFloat, paneCount: Int) -> CGFloat {
        let visiblePaneCount = CGFloat(min(max(paneCount, 1), 7))
        return floor(containerWidth / visiblePaneCount)
    }

    static func overlayShortcutItemSize() -> CGSize {
        CGSize(width: 176, height: 36)
    }

    static func toleranceOverviewHeight(containerHeight: CGFloat) -> CGFloat {
        min(max(floor(containerHeight * 0.34), 220), 320)
    }

    static func toleranceDetailHeight() -> CGFloat {
        260
    }

    static func clampedToleranceHeight(
        proposedHeight: CGFloat,
        containerHeight: CGFloat,
        reservedUpperHeight: CGFloat
    ) -> CGFloat {
        let availableHeight = max(
            containerHeight - reservedUpperHeight - toleranceResizeHandleHeight,
            1
        )
        let minimumHeight = min(180, availableHeight)
        let maximumHeight = max(minimumHeight, min(520, floor(availableHeight)))
        return min(max(floor(proposedHeight), minimumHeight), maximumHeight)
    }

    static func toleranceControlWidth(containerWidth: CGFloat) -> CGFloat {
        min(max(floor(containerWidth * 0.20), 240), 320)
    }

    static func fittedImageSize(imageSize: CGSize, viewport: CGSize, zoomScale: CGFloat) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }

        let safeScale = max(1, zoomScale)
        let safeImageSize: CGSize
        if imageSize.width > 0, imageSize.height > 0 {
            safeImageSize = imageSize
        } else {
            safeImageSize = viewport
        }

        let widthRatio = viewport.width / safeImageSize.width
        let heightRatio = viewport.height / safeImageSize.height
        let fitScale = min(widthRatio, heightRatio)

        return CGSize(
            width: floor(safeImageSize.width * fitScale * safeScale),
            height: floor(safeImageSize.height * fitScale * safeScale)
        )
    }

    static func requiredRenderPixelDimension(
        originalPixelSize: CGSize,
        renderedPointSize: CGSize,
        displayScale: CGFloat
    ) -> CGFloat {
        let originalMaximum = max(originalPixelSize.width, originalPixelSize.height)
        let renderedMaximum = max(renderedPointSize.width, renderedPointSize.height)
        let requiredPixels = max(renderedMaximum * max(displayScale, 1), 1)
        let bucketSize: CGFloat = 1024
        let bucketedPixels = ceil(requiredPixels / bucketSize) * bucketSize

        guard originalMaximum > 0 else {
            return bucketedPixels
        }
        return min(originalMaximum, bucketedPixels)
    }

    static func overlayContentSize(baseContentSize: CGSize, overlayContentSize: CGSize, lockToBaseGeometry: Bool) -> CGSize {
        lockToBaseGeometry ? baseContentSize : overlayContentSize
    }

    static func pannableContentSize(fittedContentSize: CGSize, viewport: CGSize, zoomScale: CGFloat) -> CGSize {
        guard zoomScale > 1 else { return fittedContentSize }

        return CGSize(
            width: max(fittedContentSize.width, viewport.width * zoomScale),
            height: max(fittedContentSize.height, viewport.height * zoomScale)
        )
    }

    static func imageDrawRect(imageSize: CGSize, container: CGSize, contentMode: ContentMode) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let widthRatio = container.width / imageSize.width
        let heightRatio = container.height / imageSize.height
        let scale = contentMode == .fill ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
        let drawSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: (container.width - drawSize.width) * 0.5,
            y: (container.height - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    static func imageDrawRectLockedToBounds(container: CGSize) -> CGRect {
        CGRect(origin: .zero, size: container)
    }

    static func maximumPanOffset(viewport: CGSize, contentSize: CGSize) -> CGSize {
        CGSize(
            width: max((contentSize.width - viewport.width) * 0.5, 0),
            height: max((contentSize.height - viewport.height) * 0.5, 0)
        )
    }

    static func normalizedPan(
        start: CGSize,
        translation: CGSize,
        viewport: CGSize,
        contentSize: CGSize
    ) -> CGSize {
        let maximumOffset = maximumPanOffset(viewport: viewport, contentSize: contentSize)
        return CGSize(
            width: normalizedPanAxis(start: start.width, translation: translation.width, maximumOffset: maximumOffset.width),
            height: normalizedPanAxis(start: start.height, translation: translation.height, maximumOffset: maximumOffset.height)
        )
    }

    static func actualPanOffset(
        normalizedPan: CGSize,
        viewport: CGSize,
        contentSize: CGSize
    ) -> CGSize {
        let maximumOffset = maximumPanOffset(viewport: viewport, contentSize: contentSize)
        return CGSize(
            width: clampedNormalizedPanAxis(normalizedPan.width) * maximumOffset.width,
            height: clampedNormalizedPanAxis(normalizedPan.height) * maximumOffset.height
        )
    }

    static func anchoredNormalizedPan(
        normalizedPan: CGSize,
        from oldZoomScale: CGFloat,
        to newZoomScale: CGFloat,
        anchor: CGPoint,
        containerSize: CGSize,
        imageSize: CGSize,
        viewport: CGSize
    ) -> CGSize {
        guard oldZoomScale > 0, newZoomScale > 0 else { return .zero }

        let oldFittedSize = fittedImageSize(
            imageSize: imageSize,
            viewport: viewport,
            zoomScale: oldZoomScale
        )
        let oldContentSize = pannableContentSize(
            fittedContentSize: oldFittedSize,
            viewport: viewport,
            zoomScale: oldZoomScale
        )
        let oldOffset = actualPanOffset(
            normalizedPan: normalizedPan,
            viewport: viewport,
            contentSize: oldContentSize
        )

        let newFittedSize = fittedImageSize(
            imageSize: imageSize,
            viewport: viewport,
            zoomScale: newZoomScale
        )
        let newContentSize = pannableContentSize(
            fittedContentSize: newFittedSize,
            viewport: viewport,
            zoomScale: newZoomScale
        )
        let newMaximumOffset = maximumPanOffset(
            viewport: viewport,
            contentSize: newContentSize
        )
        let zoomRatio = newZoomScale / oldZoomScale
        let anchorOffset = CGSize(
            width: anchor.x - (containerSize.width * 0.5),
            height: anchor.y - (containerSize.height * 0.5)
        )
        let anchoredOffset = CGSize(
            width: (oldOffset.width * zoomRatio) + (anchorOffset.width * (1 - zoomRatio)),
            height: (oldOffset.height * zoomRatio) + (anchorOffset.height * (1 - zoomRatio))
        )

        return CGSize(
            width: normalizedOffsetAxis(anchoredOffset.width, maximumOffset: newMaximumOffset.width),
            height: normalizedOffsetAxis(anchoredOffset.height, maximumOffset: newMaximumOffset.height)
        )
    }

    static func clampedNormalizedPan(_ value: CGSize) -> CGSize {
        CGSize(width: clampedNormalizedPanAxis(value.width), height: clampedNormalizedPanAxis(value.height))
    }

    private static func normalizedPanAxis(start: CGFloat, translation: CGFloat, maximumOffset: CGFloat) -> CGFloat {
        guard maximumOffset > 0 else { return 0 }
        return clampedNormalizedPanAxis(start + (translation / maximumOffset))
    }

    private static func normalizedOffsetAxis(_ offset: CGFloat, maximumOffset: CGFloat) -> CGFloat {
        guard maximumOffset > 0 else { return 0 }
        return clampedNormalizedPanAxis(offset / maximumOffset)
    }

    private static func clampedNormalizedPanAxis(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }
}
