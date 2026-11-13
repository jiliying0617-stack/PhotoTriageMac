import Foundation
import ImageIO
import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct CompareTolerancePairIndices: Equatable, Sendable {
    let baseIndex: Int
    let overlayIndex: Int
}

enum CompareTolerancePairing {
    static func overviewPairs(assetCount: Int) -> [CompareTolerancePairIndices] {
        guard assetCount >= 2 else { return [] }
        if assetCount == 2 {
            return [CompareTolerancePairIndices(baseIndex: 1, overlayIndex: 0)]
        }

        let sequentialPairs = (1..<assetCount).map { baseIndex in
            CompareTolerancePairIndices(
                baseIndex: baseIndex,
                overlayIndex: baseIndex - 1
            )
        }
        return sequentialPairs + [
            CompareTolerancePairIndices(baseIndex: 0, overlayIndex: assetCount - 1)
        ]
    }

    static func detailPair(
        assetCount: Int,
        focusedIndex: Int,
        selectedOverlayIndex: Int?
    ) -> CompareTolerancePairIndices? {
        guard assetCount >= 2, (0..<assetCount).contains(focusedIndex) else { return nil }
        if let selectedOverlayIndex,
           (0..<assetCount).contains(selectedOverlayIndex),
           selectedOverlayIndex != focusedIndex {
            return CompareTolerancePairIndices(baseIndex: focusedIndex, overlayIndex: selectedOverlayIndex)
        }

        return CompareTolerancePairIndices(
            baseIndex: focusedIndex,
            overlayIndex: focusedIndex == 0 ? assetCount - 1 : focusedIndex - 1
        )
    }
}

struct CompareTolerancePair: Identifiable {
    let baseAsset: AssetRecord
    let baseFileURL: URL?
    let overlayAsset: AssetRecord
    let overlayFileURL: URL?
    let baseIndex: Int
    let overlayIndex: Int
    let refreshSignature: String

    var id: String {
        "\(baseAsset.id.uuidString)|\(overlayAsset.id.uuidString)"
    }
}

struct CompareTolerancePanel: View {
    let pair: CompareTolerancePair
    let zoomScale: CGFloat
    @Binding var pan: CGSize
    let tolerance: Int
    let showsSubToleranceDifferences: Bool
    let onZoom: (CompareZoomRequest) -> Void

#if canImport(AppKit)
    @ObservedObject var store: CompareToleranceStore
#endif

    var body: some View {
        resultStage
            .background(Color(nsColor: NSColor(calibratedWhite: 0.028, alpha: 1)))
            .accessibilityLabel("容差对比结果，第 \(pair.baseIndex + 1) 张对比第 \(pair.overlayIndex + 1) 张")
    }

    private var resultStage: some View {
        ZStack {
            Color(nsColor: NSColor(calibratedWhite: 0.028, alpha: 1))

#if canImport(AppKit)
            if let result = store.result(for: requestKey) {
                toleranceViewport(result)
            } else if let latestResult = store.latestResult(for: pair.id) {
                toleranceViewport(latestResult)
                    .overlay(alignment: .topTrailing) {
                        if store.isLoading(requestKey) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.78))
                                .padding(10)
                        }
                    }
            } else if let failureMessage = store.failureMessage(for: requestKey) {
                ContentUnavailableView(
                    "无法生成容差图",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failureMessage)
                )
                .foregroundStyle(.white.opacity(0.58))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.72))
            }
#else
            Color.white.opacity(0.03)
#endif
        }
        .overlay(alignment: .bottomLeading) {
            toleranceLegend
                .padding(10)
                .allowsHitTesting(false)
        }
        .clipped()
    }

#if canImport(AppKit)
    private func toleranceViewport(_ result: CompareToleranceResult) -> some View {
        GeometryReader { proxy in
            let viewport = CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
            let imageSize = CGSize(width: result.image.width, height: result.image.height)
            let contentSize = CompareLayoutMetrics.fittedImageSize(
                imageSize: imageSize,
                viewport: viewport,
                zoomScale: zoomScale
            )
            let panContentSize = CompareLayoutMetrics.pannableContentSize(
                fittedContentSize: contentSize,
                viewport: viewport,
                zoomScale: zoomScale
            )
            let actualOffset = CompareLayoutMetrics.actualPanOffset(
                normalizedPan: pan,
                viewport: viewport,
                contentSize: panContentSize
            )

            ZStack {
                Image(decorative: result.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .position(
                        x: (proxy.size.width * 0.5) + actualOffset.width,
                        y: (proxy.size.height * 0.5) + actualOffset.height
                    )
                    .allowsHitTesting(false)
                    .accessibilityLabel("容差对比结果，差异像素占比 \(result.differencePercentageText)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                ScrollWheelZoomMonitor { event in
                    onZoom(
                        CompareZoomRequest(
                            deltaY: event.deltaY,
                            anchor: event.location,
                            containerSize: proxy.size,
                            viewport: viewport,
                            imageSize: imageSize
                        )
                    )
                }
            }
            .overlay {
                CompareDragSurface(
                    pan: $pan,
                    viewport: viewport,
                    contentSize: panContentSize,
                    allowsContextMenu: false,
                    onDraggingChanged: { _ in },
                    onRevealInFinder: nil,
                    onApplyRating: { _ in },
                    onApplyPriorityTag: { _ in },
                    onClearPriorityTag: {},
                    onClearAllTags: {},
                    onSaveGIF: { _ in }
                )
            }
        }
        .clipped()
    }
#endif

    private var toleranceLegend: some View {
        HStack(spacing: 12) {
            Text(store.usesOriginalResolution ? "原图像素检测" : "快速预览 · ≤4096px")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.72))
            legendItem(color: .red, title: "大于容差")
            if showsSubToleranceDifferences {
                legendItem(
                    color: Color(red: 0.15, green: 0.41, blue: 1),
                    title: "小于容差"
                )
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

#if canImport(AppKit)
    private var requestKey: String {
        CompareToleranceStore.requestKey(
            pair: pair,
            tolerance: tolerance,
            showsSubToleranceDifferences: showsSubToleranceDifferences,
            originalResolution: store.usesOriginalResolution
        )
    }
#endif
}

struct CompareToleranceResizeHandle: View {
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void
    let onNudge: (CGFloat) -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(calibratedWhite: 0.025, alpha: 1))

            Rectangle()
                .fill(Color.white.opacity(isHovered ? 0.26 : 0.12))
                .frame(height: 1)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.72 : 0.30))
                .frame(width: 36, height: 3)
        }
        .frame(height: CompareLayoutMetrics.toleranceResizeHandleHeight)
        .contentShape(Rectangle())
        .onHover { isInside in
            isHovered = isInside
#if canImport(AppKit)
            (isInside ? NSCursor.resizeUpDown : NSCursor.arrow).set()
#endif
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    onResize(value.translation.height)
                }
                .onEnded { _ in
                    onResizeEnd()
                }
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("调整容差区域高度")
        .accessibilityHint("上下拖动调整容差图区域高度")
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onNudge(24)
            case .decrement:
                onNudge(-24)
            @unknown default:
                break
            }
        }
    }
}

struct CompareToleranceSlider: View {
    @Binding var value: Double
    let onValueChange: (Int) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

    private let thumbDiameter: CGFloat = CompareToleranceSliderMetrics.thumbDiameter
    private let maximumValue = Double(CompareToleranceSliderMetrics.maximumValue)

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - thumbDiameter, 1)
            let progress = min(max(value / maximumValue, 0), 1)
            let filledWidth = trackWidth * progress
            let thumbOffset = trackWidth * progress

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.13))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    }
                    .frame(width: trackWidth, height: 7)
                    .offset(x: thumbDiameter * 0.5)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.15, green: 0.41, blue: 1))
                        .frame(width: filledWidth)

                    Rectangle()
                        .fill(Color(red: 1, green: 0.08, blue: 0.10))
                        .frame(width: max(trackWidth - filledWidth, 0))
                        .offset(x: filledWidth)
                }
                .frame(width: trackWidth, height: 7)
                .clipShape(Capsule(style: .continuous))
                .offset(x: thumbDiameter * 0.5)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay {
                        Circle()
                            .stroke(
                                Color(red: 1, green: 0.16, blue: 0.20)
                                    .opacity(isHovered || isDragging ? 0.95 : 0.45),
                                lineWidth: isHovered || isDragging ? 2 : 1
                            )
                    }
                    .overlay {
                        Circle()
                            .fill(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1)))
                            .frame(width: 6, height: 6)
                    }
                    .shadow(color: .black.opacity(0.48), radius: 3, y: 1)
                    .offset(x: thumbOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(for: gesture.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 38)
        .onHover { isInside in
            isHovered = isInside
#if canImport(AppKit)
            (isInside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
#endif
        }
        .onDisappear {
#if canImport(AppKit)
            NSCursor.arrow.set()
#endif
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("像素差异容差")
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityHint("左右拖动调整；蓝色区域表示容差内，红色区域表示超过容差")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setValue(Int(value.rounded()) + 1)
            case .decrement:
                setValue(Int(value.rounded()) - 1)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(for locationX: CGFloat, trackWidth: CGFloat) {
        let newValue = CompareToleranceSliderMetrics.value(
            at: locationX,
            controlWidth: trackWidth + thumbDiameter
        )
        setValue(newValue)
    }

    private func setValue(_ newValue: Int) {
        let clampedValue = min(max(newValue, 0), Int(maximumValue))
        guard clampedValue != Int(value.rounded()) else { return }
        value = Double(clampedValue)
        onValueChange(clampedValue)
    }
}

enum CompareToleranceSliderMetrics {
    static let thumbDiameter: CGFloat = 24
    static let maximumValue = 255

    static func value(at locationX: CGFloat, controlWidth: CGFloat) -> Int {
        let trackWidth = max(controlWidth - thumbDiameter, 1)
        let trackX = min(max(locationX - (thumbDiameter * 0.5), 0), trackWidth)
        return Int(((trackX / trackWidth) * CGFloat(maximumValue)).rounded())
    }
}

#if canImport(AppKit)
struct CompareToleranceControlPanel: View {
    let pairs: [CompareTolerancePair]
    let tolerance: Int
    @Binding var toleranceSliderValue: Double
    @Binding var showsSubToleranceDifferences: Bool
    let onToleranceChange: (Int) -> Void
    let onSubToleranceVisibilityChange: (Bool) -> Void
    @ObservedObject var store: CompareToleranceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red)

                Text("像素差异")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.62))
                }
            }

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    metricRow(title: "最大差异", value: "\(maximumDifference)")
                    metricRow(title: "差异像素", value: differingPixelCount.formatted())
                    metricRow(title: "占比", value: differencePercentageText)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("容差")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                    Spacer()
                    Text("\(Int(toleranceSliderValue.rounded()))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                }

                CompareToleranceSlider(
                    value: $toleranceSliderValue,
                    onValueChange: onToleranceChange
                )
            }

            Toggle("显示小于容差的蓝色差异", isOn: $showsSubToleranceDifferences)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .onChange(of: showsSubToleranceDifferences) { _, isVisible in
                    onSubToleranceVisibilityChange(isVisible)
                }

            Toggle("原图精密检测（较慢）", isOn: $store.usesOriginalResolution)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.74))
                .help("逐个检测原图像素。显示图适当缩小，但保留细小差异；统计按原图像素计算。")

            VStack(alignment: .leading, spacing: 9) {
                legendRow(color: .red, title: "大于容差")
                legendRow(
                    color: Color(red: 0.15, green: 0.41, blue: 1),
                    title: "小于容差"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.038, alpha: 1)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }

    private var results: [CompareToleranceResult] {
        pairs.compactMap { pair in
            store.result(
                for: CompareToleranceStore.requestKey(
                    pair: pair,
                    tolerance: tolerance,
                    showsSubToleranceDifferences: showsSubToleranceDifferences,
                    originalResolution: store.usesOriginalResolution
                )
            ) ?? store.latestResult(for: pair.id)
        }
    }

    private var isLoading: Bool {
        pairs.contains { pair in
            store.isLoading(
                CompareToleranceStore.requestKey(
                    pair: pair,
                    tolerance: tolerance,
                    showsSubToleranceDifferences: showsSubToleranceDifferences,
                    originalResolution: store.usesOriginalResolution
                )
            )
        }
    }

    private var maximumDifference: Int {
        results.map(\.maximumDifference).max() ?? 0
    }

    private var differingPixelCount: Int {
        results.reduce(0) { $0 + $1.differingPixelCount }
    }

    private var totalPixelCount: Int {
        results.reduce(0) { $0 + $1.totalPixelCount }
    }

    private var differencePercentageText: String {
        guard totalPixelCount > 0 else { return "0.00%" }
        let percentage = (Double(differingPixelCount) / Double(totalPixelCount)) * 100
        return percentage.formatted(.number.precision(.fractionLength(2))) + "%"
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
        }
    }

    private func legendRow(color: Color, title: String) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
    }
}
#endif

#if canImport(AppKit)
struct CompareToleranceResult: @unchecked Sendable {
    let image: CGImage
    let maximumDifference: Int
    let differingPixelCount: Int
    let totalPixelCount: Int

    var differencePercentageText: String {
        guard totalPixelCount > 0 else { return "0.00%" }
        let percentage = (Double(differingPixelCount) / Double(totalPixelCount)) * 100
        return percentage.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}

struct CompareToleranceAnalysis: Sendable {
    let width: Int
    let height: Int
    let differences: [UInt8]
    let backgroundGrayscale: [UInt8]
    let maximumDifference: Int
    let differenceHistogram: [Int]
    var displayPixels: CompareToleranceDisplayPixels? = nil

    var totalPixelCount: Int {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        return width > 0 && height > 0 && !overflow ? count : 0
    }
}

struct CompareToleranceDisplayPixels: Sendable {
    let width: Int
    let height: Int
    let differences: [UInt8]
    let grayscale: [UInt8]
}

private enum CompareToleranceRenderError: LocalizedError {
    case missingFile
    case unreadableImage(URL)
    case dimensionMismatch(
        baseWidth: Int,
        baseHeight: Int,
        overlayWidth: Int,
        overlayHeight: Int
    )
    case unableToCreateBitmap
    case memoryLimit

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "图片路径缺失"
        case let .unreadableImage(fileURL):
            let parentName = fileURL.deletingLastPathComponent().lastPathComponent
            return "图片读取失败：\(parentName)/\(fileURL.lastPathComponent)"
        case let .dimensionMismatch(baseWidth, baseHeight, overlayWidth, overlayHeight):
            return "图片尺寸不一致：\(baseWidth)×\(baseHeight) / \(overlayWidth)×\(overlayHeight)"
        case .unableToCreateBitmap:
            return "无法生成像素容差图"
        case .memoryLimit:
            return "原图检测超过本机安全内存预算。请用快速预览，或裁切需要检查的区域后比较。"
        }
    }
}

private final class CompareToleranceRenderCoordinator: @unchecked Sendable {
    static let shared = CompareToleranceRenderCoordinator()

    private let lock = NSLock()
    private var latestTokens: [String: UUID] = [:]

    func replaceToken(for pairID: String) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let token = UUID()
        latestTokens[pairID] = token
        return token
    }

    func isCurrent(_ token: UUID, for pairID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return latestTokens[pairID] == token
    }

    func cancel(_ pairID: String) {
        lock.lock()
        latestTokens.removeValue(forKey: pairID)
        lock.unlock()
    }
}

@MainActor
final class CompareToleranceStore: ObservableObject {
    @Published var usesOriginalResolution = false
    private enum LoadState {
        case loading
        case loaded(CompareToleranceResult)
        case failed(String)
    }

    @Published private var states: [String: LoadState] = [:]
    private var loadTokens: [String: UUID] = [:]
    private var accessOrder: [String] = []
    private var latestResults: [String: CompareToleranceResult] = [:]
    private var latestResultAccessOrder: [String] = []
    private var activePairIDs: Set<String> = []
    private var pendingLoadTask: Task<Void, Never>?
    private let stateLimit = 24
    private static let renderQueue = DispatchQueue(
        label: "com.jiliying.phototriage.tolerance-render",
        qos: .userInitiated
    )

    static func requestKey(
        pair: CompareTolerancePair,
        tolerance: Int = 0,
        showsSubToleranceDifferences: Bool = true,
        originalResolution: Bool = false
    ) -> String {
        [
            analysisKey(pair: pair, originalResolution: originalResolution),
            "tolerance=\(min(max(tolerance, 0), 255))",
            "showsSubTolerance=\(showsSubToleranceDifferences)"
        ].joined(separator: "|")
    }

    static func analysisKey(pair: CompareTolerancePair, originalResolution: Bool = false) -> String {
        [
            pair.baseAsset.id.uuidString,
            pair.baseFileURL?.path ?? "missing",
            "\(pair.baseAsset.normalizedRotationDegrees)",
            pair.overlayAsset.id.uuidString,
            pair.overlayFileURL?.path ?? "missing",
            "\(pair.overlayAsset.normalizedRotationDegrees)",
            pair.refreshSignature,
            "native=\(originalResolution)"
        ].joined(separator: "|")
    }

    func result(for key: String) -> CompareToleranceResult? {
        guard case let .loaded(result) = states[key] else { return nil }
        return result
    }

    func latestResult(for pairID: String) -> CompareToleranceResult? {
        latestResults[pairID]
    }

    func isLoading(_ key: String) -> Bool {
        guard case .loading = states[key] else { return false }
        return true
    }

    func failureMessage(for key: String) -> String? {
        guard case let .failed(message) = states[key] else { return nil }
        return message
    }

    func load(
        pairs: [CompareTolerancePair],
        tolerance: Int = 0,
        showsSubToleranceDifferences: Bool = true,
        debounce: Bool = false
    ) {
        pendingLoadTask?.cancel()
        pendingLoadTask = nil

        guard debounce else {
            performLoad(
                pairs: pairs,
                tolerance: tolerance,
                showsSubToleranceDifferences: showsSubToleranceDifferences
            )
            return
        }

        pendingLoadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 16_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.pendingLoadTask = nil
            self?.performLoad(
                pairs: pairs,
                tolerance: tolerance,
                showsSubToleranceDifferences: showsSubToleranceDifferences
            )
        }
    }

    private func performLoad(
        pairs: [CompareTolerancePair],
        tolerance: Int,
        showsSubToleranceDifferences: Bool
    ) {
        let newPairIDs = Set(pairs.map(\.id))
        for id in activePairIDs.subtracting(newPairIDs) {
            CompareToleranceRenderCoordinator.shared.cancel(id)
        }
        activePairIDs = newPairIDs
        latestResults = latestResults.filter { newPairIDs.contains($0.key) }
        latestResultAccessOrder.removeAll { !newPairIDs.contains($0) }
        let activeKeys = Set(
            pairs.map { pair in
                Self.requestKey(
                    pair: pair,
                    tolerance: tolerance,
                    showsSubToleranceDifferences: showsSubToleranceDifferences,
                    originalResolution: usesOriginalResolution
                )
            }
        )
        states = states.filter { activeKeys.contains($0.key) }
        loadTokens = loadTokens.filter { activeKeys.contains($0.key) }
        accessOrder.removeAll { !activeKeys.contains($0) }

        for pair in pairs {
            load(
                pair: pair,
                tolerance: tolerance,
                showsSubToleranceDifferences: showsSubToleranceDifferences
            )
        }
    }

    private func load(
        pair: CompareTolerancePair,
        tolerance: Int,
        showsSubToleranceDifferences: Bool
    ) {
        let clampedTolerance = min(max(tolerance, 0), 255)
        let key = Self.requestKey(
            pair: pair,
            tolerance: clampedTolerance,
            showsSubToleranceDifferences: showsSubToleranceDifferences,
            originalResolution: usesOriginalResolution
        )
        if case .loading = states[key] { return }
        if case .loaded = states[key] { return }

        if let cached = CompareToleranceResultCache.shared.result(for: key) {
            setLatestResult(cached, for: pair.id)
            setState(.loaded(cached), for: key)
            return
        }

        let pairID = pair.id
        let token = CompareToleranceRenderCoordinator.shared.replaceToken(for: pairID)
        loadTokens[key] = token
        setState(.loading, for: key)
        let baseURL = pair.baseFileURL
        let overlayURL = pair.overlayFileURL
        let baseRotation = pair.baseAsset.normalizedRotationDegrees
        let overlayRotation = pair.overlayAsset.normalizedRotationDegrees
        let originalResolution = usesOriginalResolution
        let analysisKey = Self.analysisKey(pair: pair, originalResolution: originalResolution)

        Self.renderQueue.async {
            guard CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID) else {
                return
            }
            let rendered: Result<CompareToleranceResult?, Error> = autoreleasepool {
                Result {
                    guard let baseURL, let overlayURL else {
                        throw CompareToleranceRenderError.missingFile
                    }

                    let analysis: CompareToleranceAnalysis
                    if let cachedAnalysis = CompareToleranceAnalysisCache.shared.analysis(for: analysisKey) {
                        analysis = cachedAnalysis
                    } else {
                        analysis = try CompareToleranceRenderer.analyze(
                            baseFileURL: baseURL,
                            baseRotationDegrees: baseRotation,
                            overlayFileURL: overlayURL,
                            overlayRotationDegrees: overlayRotation,
                            originalResolution: originalResolution,
                            shouldContinue: { CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID) }
                        )
                        if CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID) {
                            CompareToleranceAnalysisCache.shared.insert(analysis, for: analysisKey)
                        }
                    }

                    guard CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID) else {
                        return nil
                    }

                    return try CompareToleranceRenderer.render(
                        analysis: analysis,
                        tolerance: clampedTolerance,
                        showsSubToleranceDifferences: showsSubToleranceDifferences,
                        shouldContinue: {
                            CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID)
                        }
                    )
                }
            }

            guard case let .success(result?) = rendered,
                  CompareToleranceRenderCoordinator.shared.isCurrent(token, for: pairID) else {
                if case .failure = rendered {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.loadTokens[key] == token else { return }
                        self.loadTokens.removeValue(forKey: key)
                        if case let .failure(error) = rendered {
                            self.latestResults.removeValue(forKey: pairID)
                            self.setState(.failed(error.localizedDescription), for: key)
                        }
                    }
                }
                return
            }

            if case .success = rendered {
                CompareToleranceResultCache.shared.insert(result, for: key)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadTokens[key] == token else { return }
                self.loadTokens.removeValue(forKey: key)
                switch rendered {
                case let .success(result?):
                    self.setLatestResult(result, for: pairID)
                    self.setState(.loaded(result), for: key)
                case .success(nil):
                    break
                case let .failure(error):
                    self.setState(.failed(error.localizedDescription), for: key)
                }
            }
        }
    }

    private func setState(_ state: LoadState, for key: String) {
        states[key] = state
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        while accessOrder.count > stateLimit {
            let staleKey = accessOrder.removeFirst()
            states.removeValue(forKey: staleKey)
            loadTokens.removeValue(forKey: staleKey)
        }
    }

    private func setLatestResult(_ result: CompareToleranceResult, for pairID: String) {
        latestResults[pairID] = result
        latestResultAccessOrder.removeAll { $0 == pairID }
        latestResultAccessOrder.append(pairID)

        while latestResultAccessOrder.count > stateLimit ||
            latestResults.values.reduce(0, { $0 + $1.image.bytesPerRow * $1.image.height }) > 192 * 1024 * 1024 {
            let stalePairID = latestResultAccessOrder.removeFirst()
            latestResults.removeValue(forKey: stalePairID)
        }
    }

    func cancelPendingLoads() {
        pendingLoadTask?.cancel()
        for id in activePairIDs { CompareToleranceRenderCoordinator.shared.cancel(id) }
        activePairIDs = []
        loadTokens = [:]
        states = [:]
        latestResults = [:]
        accessOrder = []
        latestResultAccessOrder = []
    }

    nonisolated static func clearRenderCaches() {
        CompareToleranceAnalysisCache.shared.clear()
        CompareToleranceResultCache.shared.clear()
    }
}

enum CompareToleranceRenderer {
    static let maximumComparisonDimension: CGFloat = 4096
    static let unchangedBackgroundLuminanceScale = 0.36

    static func render(
        baseFileURL: URL,
        baseRotationDegrees: Int,
        overlayFileURL: URL,
        overlayRotationDegrees: Int,
        tolerance: Int = 0,
        showsSubToleranceDifferences: Bool = true
    ) throws -> CompareToleranceResult {
        let analysis = try analyze(
            baseFileURL: baseFileURL,
            baseRotationDegrees: baseRotationDegrees,
            overlayFileURL: overlayFileURL,
            overlayRotationDegrees: overlayRotationDegrees
        )
        guard let result = try render(
            analysis: analysis,
            tolerance: tolerance,
            showsSubToleranceDifferences: showsSubToleranceDifferences
        ) else {
            throw CompareToleranceRenderError.unableToCreateBitmap
        }
        return result
    }

    static func analyze(
        baseFileURL: URL,
        baseRotationDegrees: Int,
        overlayFileURL: URL,
        overlayRotationDegrees: Int,
        originalResolution: Bool = false,
        shouldContinue: () -> Bool = { true }
    ) throws -> CompareToleranceAnalysis {
        guard shouldContinue() else { throw CancellationError() }
        if originalResolution, let size = PhotoImagePipeline.pixelSize(for: baseFileURL) {
            let estimatedBytes = Double(size.width * size.height) * 24
            let budget = min(Double(ProcessInfo.processInfo.physicalMemory) / 4, 3 * 1024 * 1024 * 1024)
            guard estimatedBytes <= budget else { throw CompareToleranceRenderError.memoryLimit }
        }
        if let baseSize = orientedPixelSize(
            for: baseFileURL,
            rotationDegrees: baseRotationDegrees
        ), let overlaySize = orientedPixelSize(
            for: overlayFileURL,
            rotationDegrees: overlayRotationDegrees
        ), baseSize != overlaySize {
            throw CompareToleranceRenderError.dimensionMismatch(
                baseWidth: baseSize.width,
                baseHeight: baseSize.height,
                overlayWidth: overlaySize.width,
                overlayHeight: overlaySize.height
            )
        }

        guard let baseImage = originalResolution ? PhotoImagePipeline.fullResolutionCGImage(for: baseFileURL) : comparisonImage(for: baseFileURL) else {
            throw CompareToleranceRenderError.unreadableImage(baseFileURL)
        }
        guard shouldContinue() else { throw CancellationError() }
        guard let overlayImage = originalResolution ? PhotoImagePipeline.fullResolutionCGImage(for: overlayFileURL) : comparisonImage(for: overlayFileURL) else {
            throw CompareToleranceRenderError.unreadableImage(overlayFileURL)
        }

        let targetSize = comparisonSize(
            image: baseImage,
            rotationDegrees: baseRotationDegrees,
            maxPixelDimension: originalResolution ? CGFloat(max(baseImage.width, baseImage.height)) : maximumComparisonDimension
        )
        guard let basePixels = renderedPixels(
            image: baseImage,
            rotationDegrees: baseRotationDegrees,
            targetSize: targetSize
        ), let overlayPixels = renderedPixels(
            image: overlayImage,
            rotationDegrees: overlayRotationDegrees,
            targetSize: targetSize
        ) else {
            throw CompareToleranceRenderError.unableToCreateBitmap
        }

        let pixelCount = targetSize.width * targetSize.height
        var differences = [UInt8](repeating: 0, count: pixelCount)
        var backgroundGrayscale = [UInt8](repeating: 0, count: pixelCount)
        var differenceHistogram = [Int](repeating: 0, count: 256)
        var maximumDifference = 0

        for pixelIndex in 0..<pixelCount {
            if pixelIndex & 0xFFFF == 0, !shouldContinue() { throw CancellationError() }
            let offset = pixelIndex * 4
            let redDifference = abs(Int(basePixels[offset]) - Int(overlayPixels[offset]))
            let greenDifference = abs(Int(basePixels[offset + 1]) - Int(overlayPixels[offset + 1]))
            let blueDifference = abs(Int(basePixels[offset + 2]) - Int(overlayPixels[offset + 2]))
            let alphaDifference = abs(Int(basePixels[offset + 3]) - Int(overlayPixels[offset + 3]))
            let difference = max(redDifference, greenDifference, blueDifference, alphaDifference)
            maximumDifference = max(maximumDifference, difference)
            differences[pixelIndex] = UInt8(difference)
            differenceHistogram[difference] += 1
            let luminance = (0.2126 * Double(basePixels[offset]))
                + (0.7152 * Double(basePixels[offset + 1]))
                + (0.0722 * Double(basePixels[offset + 2]))
            backgroundGrayscale[pixelIndex] = UInt8(
                max(
                    0,
                    min(
                        (luminance * unchangedBackgroundLuminanceScale).rounded(),
                        255
                    )
                )
            )
        }

        var analysis = CompareToleranceAnalysis(
            width: targetSize.width,
            height: targetSize.height,
            differences: differences,
            backgroundGrayscale: backgroundGrayscale,
            maximumDifference: maximumDifference,
            differenceHistogram: differenceHistogram
        )
        // Downsample with maxima once per image pair, not once per slider tick.
        // Native differences and the histogram remain unchanged for exact counts.
        analysis.displayPixels = try displayPixels(for: analysis, shouldContinue: shouldContinue)
        return analysis
    }

    static func render(
        analysis: CompareToleranceAnalysis,
        tolerance: Int = 0,
        showsSubToleranceDifferences: Bool = true,
        shouldContinue: () -> Bool = { true }
    ) throws -> CompareToleranceResult? {
        let pixelCount = analysis.totalPixelCount
        guard pixelCount > 0, analysis.differences.count == pixelCount,
              analysis.backgroundGrayscale.count == pixelCount,
              analysis.differenceHistogram.count == 256 else {
            throw CompareToleranceRenderError.unableToCreateBitmap
        }

        let clampedTolerance = min(max(tolerance, 0), 255)
        let differingPixelCount = clampedTolerance < 255
            ? analysis.differenceHistogram[(clampedTolerance + 1)...255].reduce(0, +)
            : 0
        // Bound display memory, but keep every native difference and the native histogram.
        // A display cell uses the maximum difference of its source pixels, never an average.
        guard shouldContinue() else { return nil }
        let display: CompareToleranceDisplayPixels
        do {
            display = try analysis.displayPixels ?? displayPixels(for: analysis, shouldContinue: shouldContinue)
        } catch is CancellationError { return nil }
        let outputWidth = display.width
        let outputHeight = display.height
        let (outputCount, overflow) = outputWidth.multipliedReportingOverflow(by: outputHeight)
        guard outputWidth > 0, outputHeight > 0, !overflow, outputCount <= 4_194_304,
              display.differences.count == outputCount, display.grayscale.count == outputCount else {
            throw CompareToleranceRenderError.unableToCreateBitmap
        }
        let outputDifferences = display.differences
        let outputGrayscale = display.grayscale
        var outputPixels = [UInt8](repeating: 0, count: outputCount * 4)

        for pixelIndex in 0..<outputCount {
            if pixelIndex & 0xFFFF == 0, !shouldContinue() { return nil }
            let offset = pixelIndex * 4
            let difference = Int(outputDifferences[pixelIndex])
            if difference > clampedTolerance {
                outputPixels[offset] = 255
                outputPixels[offset + 1] = 0
                outputPixels[offset + 2] = 0
            } else if showsSubToleranceDifferences, difference > 0 {
                outputPixels[offset] = 38
                outputPixels[offset + 1] = 105
                outputPixels[offset + 2] = 255
            } else {
                let gray = outputGrayscale[pixelIndex]
                outputPixels[offset] = gray
                outputPixels[offset + 1] = gray
                outputPixels[offset + 2] = gray
            }
            outputPixels[offset + 3] = 255
        }

        guard let outputImage = makeImage(pixels: outputPixels, width: outputWidth, height: outputHeight) else {
            throw CompareToleranceRenderError.unableToCreateBitmap
        }
        return CompareToleranceResult(image: outputImage, maximumDifference: analysis.maximumDifference,
            differingPixelCount: differingPixelCount, totalPixelCount: pixelCount)
    }

    private static func displayPixels(for analysis: CompareToleranceAnalysis, shouldContinue: () -> Bool) throws -> CompareToleranceDisplayPixels {
        let pixelCount = analysis.totalPixelCount
        guard shouldContinue() else { throw CancellationError() }
        if max(analysis.width, analysis.height) <= 4096 && pixelCount <= 4_194_304 {
            return CompareToleranceDisplayPixels(width: analysis.width, height: analysis.height,
                differences: analysis.differences, grayscale: analysis.backgroundGrayscale)
        }
        let scale = min(1, 4096.0 / Double(max(analysis.width, analysis.height)),
            sqrt(4_194_304.0 / Double(pixelCount)))
        let outputWidth = max(1, Int(Double(analysis.width) * scale))
        let outputHeight = max(1, Int(Double(analysis.height) * scale))
        let outputCount = outputWidth * outputHeight
        var outputDifferences = [UInt8](repeating: 0, count: outputCount)
        var outputGrayscale = [UInt8](repeating: 0, count: outputCount)
        for y in 0..<analysis.height {
            if y % 32 == 0, !shouldContinue() { throw CancellationError() }
            let outY = min(outputHeight - 1, y * outputHeight / analysis.height)
            for x in 0..<analysis.width {
                let index = y * analysis.width + x
                let out = outY * outputWidth + min(outputWidth - 1, x * outputWidth / analysis.width)
                outputDifferences[out] = max(outputDifferences[out], analysis.differences[index])
                outputGrayscale[out] = analysis.backgroundGrayscale[index]
            }
        }
        return CompareToleranceDisplayPixels(width: outputWidth, height: outputHeight,
            differences: outputDifferences, grayscale: outputGrayscale)
    }

    private static func orientedPixelSize(
        for fileURL: URL,
        rotationDegrees: Int
    ) -> (width: Int, height: Int)? {
        guard let pixelSize = PhotoImagePipeline.pixelSize(for: fileURL) else { return nil }
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)

        if rotation == 90 || rotation == 270 {
            return (width: height, height: width)
        }
        return (width: width, height: height)
    }

    private static func comparisonImage(for fileURL: URL) -> CGImage? {
        // ImageIO already reads from a URL. Retrying the entire file as Data can
        // duplicate a huge/invalid file in memory and fall back to full decoding.
        PhotoImagePipeline.cgImage(
            for: fileURL,
            maxPixelSize: maximumComparisonDimension
        )
    }

    private static func comparisonSize(
        image: CGImage,
        rotationDegrees: Int,
        maxPixelDimension: CGFloat
    ) -> (width: Int, height: Int) {
        let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)
        let rotatedWidth = rotation == 90 || rotation == 270 ? image.height : image.width
        let rotatedHeight = rotation == 90 || rotation == 270 ? image.width : image.height
        let largestDimension = max(rotatedWidth, rotatedHeight)
        let scale = largestDimension > Int(maxPixelDimension)
            ? maxPixelDimension / CGFloat(largestDimension)
            : 1

        return (
            width: max(1, Int((CGFloat(rotatedWidth) * scale).rounded())),
            height: max(1, Int((CGFloat(rotatedHeight) * scale).rounded()))
        )
    }

    private static func renderedPixels(
        image: CGImage,
        rotationDegrees: Int,
        targetSize: (width: Int, height: Int)
    ) -> [UInt8]? {
        let bytesPerRow = targetSize.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * targetSize.height)
        let createdContext = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: targetSize.width,
                    height: targetSize.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: comparisonColorSpace(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }

            let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)
            context.interpolationQuality = .none
            context.clear(CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
            context.translateBy(x: CGFloat(targetSize.width) * 0.5, y: CGFloat(targetSize.height) * 0.5)
            context.rotate(by: CGFloat(rotation) * .pi / 180)

            let drawSize = rotation == 90 || rotation == 270
                ? CGSize(width: targetSize.height, height: targetSize.width)
                : CGSize(width: targetSize.width, height: targetSize.height)
            context.draw(
                image,
                in: CGRect(
                    x: -drawSize.width * 0.5,
                    y: -drawSize.height * 0.5,
                    width: drawSize.width,
                    height: drawSize.height
                )
            )
            return true
        }

        return createdContext ? pixels : nil
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: comparisonColorSpace(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func comparisonColorSpace() -> CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}

private final class CompareToleranceResultBox: NSObject {
    let result: CompareToleranceResult

    init(_ result: CompareToleranceResult) {
        self.result = result
    }
}

private final class CompareToleranceAnalysisBox: NSObject {
    let analysis: CompareToleranceAnalysis

    init(_ analysis: CompareToleranceAnalysis) {
        self.analysis = analysis
    }
}

private final class CompareToleranceAnalysisCache: @unchecked Sendable {
    static let shared = CompareToleranceAnalysisCache()

    private let cache = NSCache<NSString, CompareToleranceAnalysisBox>()

    private init() {
        cache.countLimit = 16
        cache.totalCostLimit = 320 * 1024 * 1024
    }

    func analysis(for key: String) -> CompareToleranceAnalysis? {
        cache.object(forKey: key as NSString)?.analysis
    }

    func insert(_ analysis: CompareToleranceAnalysis, for key: String) {
        let cost = max(
            1,
            analysis.differences.count + analysis.backgroundGrayscale.count
                + (analysis.displayPixels.map { $0.differences.count + $0.grayscale.count } ?? 0)
        )
        cache.setObject(
            CompareToleranceAnalysisBox(analysis),
            forKey: key as NSString,
            cost: cost
        )
    }
    func clear() { cache.removeAllObjects() }
}

private final class CompareToleranceResultCache: @unchecked Sendable {
    static let shared = CompareToleranceResultCache()

    private let cache = NSCache<NSString, CompareToleranceResultBox>()

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func result(for key: String) -> CompareToleranceResult? {
        cache.object(forKey: key as NSString)?.result
    }

    func insert(_ result: CompareToleranceResult, for key: String) {
        let cost = max(1, result.image.bytesPerRow * result.image.height)
        cache.setObject(CompareToleranceResultBox(result), forKey: key as NSString, cost: cost)
    }
    func clear() { cache.removeAllObjects() }
}
#endif
