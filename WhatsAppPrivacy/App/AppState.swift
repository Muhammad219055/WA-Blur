import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isPrivacyEnabled: Bool = true
    @Published var isWhatsAppRunning: Bool = false
    @Published var whatsAppFrame: CGRect?
    @Published var accessibilityTrusted: Bool = false

    func togglePrivacy() {
        isPrivacyEnabled.toggle()
    }
}
