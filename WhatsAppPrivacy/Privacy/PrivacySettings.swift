import Foundation

@MainActor
final class PrivacySettings: ObservableObject {
    private static let renderStyleKey = "privacyRenderStyle"
    private static let intensityKey = "privacyIntensity"
    private static let regionScopeKey = "privacyRegionScope"
    private static let revealModeKey = "privacyRevealMode"
    private static let filterOptionsKey = "privacyFilterOptions"

    @Published var renderStyle: PrivacyRenderStyle {
        didSet { defaults.set(renderStyle.rawValue, forKey: Self.renderStyleKey) }
    }

    @Published var intensity: PrivacyIntensity {
        didSet { defaults.set(intensity.rawValue, forKey: Self.intensityKey) }
    }

    @Published var regionScope: PrivacyRegionScope {
        didSet {
            defaults.set(regionScope.rawValue, forKey: Self.regionScopeKey)
            switch regionScope {
            case .fullWindow:
                if filterOptions != .everything { filterOptions = .everything }
            case .sidebarOnly:
                if filterOptions != .chatListOnly { filterOptions = .chatListOnly }
            case .chatOnly:
                if filterOptions != .conversationOnly { filterOptions = .conversationOnly }
            case .custom:
                break
            }
        }
    }

    @Published var revealMode: PrivacyRevealMode {
        didSet { defaults.set(revealMode.rawValue, forKey: Self.revealModeKey) }
    }

    @Published var filterOptions: PrivacyFilterOptions {
        didSet {
            if let data = try? JSONEncoder().encode(filterOptions) {
                defaults.set(data, forKey: Self.filterOptionsKey)
            }
            let matchingScope: PrivacyRegionScope
            if filterOptions == .everything {
                matchingScope = .fullWindow
            } else if filterOptions == .chatListOnly {
                matchingScope = .sidebarOnly
            } else if filterOptions == .conversationOnly {
                matchingScope = .chatOnly
            } else {
                matchingScope = .custom
            }
            if regionScope != matchingScope {
                regionScope = matchingScope
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.renderStyle = (defaults.string(forKey: Self.renderStyleKey))
            .flatMap(PrivacyRenderStyle.init(rawValue:)) ?? .blur
        self.intensity = (defaults.string(forKey: Self.intensityKey))
            .flatMap(PrivacyIntensity.init(rawValue:)) ?? .medium
        let savedRegion = (defaults.string(forKey: Self.regionScopeKey))
            .flatMap(PrivacyRegionScope.init(rawValue:)) ?? .fullWindow
        self.regionScope = savedRegion
        self.revealMode = (defaults.string(forKey: Self.revealModeKey))
            .flatMap(PrivacyRevealMode.init(rawValue:)) ?? .none

        if let data = defaults.data(forKey: Self.filterOptionsKey),
           let savedFilters = try? JSONDecoder().decode(PrivacyFilterOptions.self, from: data) {
            self.filterOptions = savedFilters
        } else {
            switch savedRegion {
            case .fullWindow: self.filterOptions = .everything
            case .sidebarOnly: self.filterOptions = .chatListOnly
            case .chatOnly: self.filterOptions = .conversationOnly
            case .custom: self.filterOptions = .everything
            }
        }
    }
}
