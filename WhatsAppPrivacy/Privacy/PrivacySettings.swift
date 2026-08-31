import Foundation

@MainActor
final class PrivacySettings: ObservableObject {
    private static let renderStyleKey = "privacyRenderStyle"
    private static let intensityKey = "privacyIntensity"
    private static let regionScopeKey = "privacyRegionScope"
    private static let revealModeKey = "privacyRevealMode"

    @Published var renderStyle: PrivacyRenderStyle {
        didSet { defaults.set(renderStyle.rawValue, forKey: Self.renderStyleKey) }
    }

    @Published var intensity: PrivacyIntensity {
        didSet { defaults.set(intensity.rawValue, forKey: Self.intensityKey) }
    }

    @Published var regionScope: PrivacyRegionScope {
        didSet { defaults.set(regionScope.rawValue, forKey: Self.regionScopeKey) }
    }

    @Published var revealMode: PrivacyRevealMode {
        didSet { defaults.set(revealMode.rawValue, forKey: Self.revealModeKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.renderStyle = (defaults.string(forKey: Self.renderStyleKey))
            .flatMap(PrivacyRenderStyle.init(rawValue:)) ?? .blur
        self.intensity = (defaults.string(forKey: Self.intensityKey))
            .flatMap(PrivacyIntensity.init(rawValue:)) ?? .medium
        self.regionScope = (defaults.string(forKey: Self.regionScopeKey))
            .flatMap(PrivacyRegionScope.init(rawValue:)) ?? .fullWindow
        self.revealMode = (defaults.string(forKey: Self.revealModeKey))
            .flatMap(PrivacyRevealMode.init(rawValue:)) ?? .none
    }
}
