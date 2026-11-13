import Combine
import Foundation

@MainActor
public final class InteractionSettingsStore: ObservableObject {
    private enum Keys {
        static let wheelZoomEnabled = "PhotoTriage.Interaction.WheelZoomEnabled"
        static let naturalScrollZoom = "PhotoTriage.Interaction.NaturalScrollZoom"
    }

    @Published public var wheelZoomEnabled: Bool {
        didSet { defaults.set(wheelZoomEnabled, forKey: Keys.wheelZoomEnabled) }
    }

    @Published public var naturalScrollZoom: Bool {
        didSet { defaults.set(naturalScrollZoom, forKey: Keys.naturalScrollZoom) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wheelZoomEnabled = defaults.object(forKey: Keys.wheelZoomEnabled) as? Bool ?? true
        naturalScrollZoom = defaults.object(forKey: Keys.naturalScrollZoom) as? Bool ?? true
    }

    public func resetToDefaults() {
        wheelZoomEnabled = true
        naturalScrollZoom = true
    }

    public func adjustedZoomDelta(_ delta: CGFloat) -> CGFloat {
        naturalScrollZoom ? delta : -delta
    }
}
