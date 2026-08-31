enum PrivacyRenderStyle: String, CaseIterable, Sendable {
    case blur
    case redact

    var menuTitle: String {
        switch self {
        case .blur: return "Blur"
        case .redact: return "Redact"
        }
    }
}
