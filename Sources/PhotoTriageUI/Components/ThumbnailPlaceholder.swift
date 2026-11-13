import Foundation
import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ThumbnailPlaceholder: View {
    let asset: AssetRecord?
    let fileURL: URL?
    let contentMode: ThumbnailContentMode
    let maxPixelSize: CGFloat
    let refreshToken: UUID?

    @StateObject private var imageState = ThumbnailImageState()

    init(
        asset: AssetRecord?,
        fileURL: URL? = nil,
        contentMode: ThumbnailContentMode = .fill,
        maxPixelSize: CGFloat = 520,
        refreshToken: UUID? = nil
    ) {
        self.asset = asset
        self.fileURL = fileURL
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        self.refreshToken = refreshToken
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fillColor)
            .overlay {
#if canImport(AppKit)
                Group {
                    if let thumbnailImage = imageState.image {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: contentMode.swiftUIContentMode)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholderContent
                    }
                }
#else
                placeholderContent
#endif
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
            .task(id: thumbnailRequest) {
#if canImport(AppKit)
                await imageState.load(thumbnailRequest)
#endif
            }
            .onDisappear {
                // Lazy stacks keep offscreen cell state alive. Only the bounded
                // shared cache should retain thumbnails after their cell leaves.
                imageState.releaseImage()
            }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title2)
            Text(label)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(8)
    }

    private var fillColor: Color {
        asset == nil ? Color.secondary.opacity(0.08) : Color.blue.opacity(0.08)
    }

    private var iconName: String {
        guard let asset else { return "square.dashed" }
        return asset.isRaw ? "camera.aperture" : "photo"
    }

    private var label: String {
        guard let asset else { return "缺失" }
        return asset.format.badge
    }

    private var accessibilityLabel: String {
        guard let asset else { return "缺失素材" }
        return "\(asset.filename)，\(asset.format.badge)"
    }

    private var thumbnailRequest: ThumbnailLoadRequest {
        ThumbnailLoadRequest(
            assetID: asset?.id,
            fileURL: fileURL,
            fileSizeBytes: asset?.fileSizeBytes ?? 0,
            modificationDate: asset?.contentModificationDate,
            maxPixelSize: maxPixelSize,
            refreshToken: refreshToken
        )
    }
}

#if canImport(AppKit)
struct ThumbnailLoadRequest: Equatable {
    let assetID: UUID?
    let fileURL: URL?
    let fileSizeBytes: Int64
    let modificationDate: Date?
    let maxPixelSize: CGFloat
    let refreshToken: UUID?

    func needsRefresh(after previous: Self?) -> Bool {
        // Reusing a list slot for a different asset is not a file mutation.
        // Do not throw away a valid shared cache entry when scrolling/filtering.
        guard let previous, previous.assetID == assetID, previous.fileURL == fileURL else { return false }
        return refreshToken != previous.refreshToken
    }
}

@MainActor
final class ThumbnailImageState: ObservableObject {
    typealias Loader = @MainActor (URL, CGFloat, PhotoImageCachePolicy) async -> NSImage?
    @Published private(set) var image: NSImage?
    private var loadedRequest: ThumbnailLoadRequest?
    private var loadGeneration = UUID()

    func load(
        _ request: ThumbnailLoadRequest,
        loader: Loader = { url, size, policy in
            await PhotoImagePipeline.loadImage(for: url, maxPixelSize: size, cachePolicy: policy)
        }
    ) async {
        let generation = UUID()
        loadGeneration = generation
        guard request.assetID != nil, let url = request.fileURL else {
            releaseImage()
            return
        }
        if let previous = loadedRequest,
           previous.assetID != request.assetID || previous.fileURL != request.fileURL {
            image = nil
        }
        let policy: PhotoImageCachePolicy = request.needsRefresh(after: loadedRequest) ? .refresh : .readWrite
        let loadedImage = await loader(url, request.maxPixelSize, policy)
        guard !Task.isCancelled, loadGeneration == generation else { return }
        image = loadedImage
        loadedRequest = request
    }

    func releaseImage() {
        loadGeneration = UUID()
        image = nil
        loadedRequest = nil
    }
}
#endif

enum ThumbnailContentMode {
    case fill
    case fit

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fill:
            .fill
        case .fit:
            .fit
        }
    }
}

#if canImport(AppKit)
public enum PhotoTriageUICaches {
    public static func clearAll() {
        PhotoImagePipeline.clearCache()
        CompareToleranceStore.clearRenderCaches()
    }
}
#endif
