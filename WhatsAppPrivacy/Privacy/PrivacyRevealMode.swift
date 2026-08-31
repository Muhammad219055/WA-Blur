import Foundation

enum PrivacyRevealMode: String, CaseIterable, Sendable {
    case none
    case hoverPeek
    case modifierPeek

    var menuTitle: String {
        switch self {
        case .none: return "Strict (No Reveal)"
        case .hoverPeek: return "Hover to Peek"
        case .modifierPeek: return "Hold Option to Peek"
        }
    }
}
