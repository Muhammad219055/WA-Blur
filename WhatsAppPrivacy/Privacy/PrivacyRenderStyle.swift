enum PrivacyRenderStyle: String, CaseIterable {
    case blur
    case pixelate
    case redact

    var menuTitle: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .redact: return "Redact"
        }
    }
}
