import Foundation

@MainActor
final class PrivacySettings: ObservableObject {
    private static let renderStyleKey = "privacyRenderStyle"
    private static let intensityKey = "privacyIntensity"

    @Published var renderStyle: PrivacyRenderStyle {
        didSet { defaults.set(renderStyle.rawValue, forKey: Self.renderStyleKey) }
    }

    @Published var intensity: PrivacyIntensity {
        didSet { defaults.set(intensity.rawValue, forKey: Self.intensityKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.renderStyle = (defaults.string(forKey: Self.renderStyleKey))
            .flatMap(PrivacyRenderStyle.init(rawValue:)) ?? .blur
        self.intensity = (defaults.string(forKey: Self.intensityKey))
            .flatMap(PrivacyIntensity.init(rawValue:)) ?? .medium
    }
}
