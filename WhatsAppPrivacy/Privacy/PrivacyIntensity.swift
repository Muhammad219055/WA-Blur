enum PrivacyIntensity: String, CaseIterable {
    case low
    case medium
    case high

    var menuTitle: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Opacity of the dark layer composited on top of the render style to
    /// control how strongly the underlying content is obscured. Applies
    /// uniformly across styles (Blur, Pixelate, Redact all read this) so
    /// "intensity" means the same thing regardless of which style is active.
    var overlayOpacity: Double {
        switch self {
        case .low: return 0.15
        case .medium: return 0.35
        case .high: return 0.6
        }
    }
}
