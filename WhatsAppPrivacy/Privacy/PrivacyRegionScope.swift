import Foundation

enum PrivacyRegionScope: String, CaseIterable, Sendable {
    case fullWindow
    case sidebarOnly
    case chatOnly
    case custom

    var menuTitle: String {
        switch self {
        case .fullWindow: return "Full Window"
        case .sidebarOnly: return "Chat List Only"
        case .chatOnly: return "Conversation Only"
        case .custom: return "Custom (Granular)"
        }
    }
}
