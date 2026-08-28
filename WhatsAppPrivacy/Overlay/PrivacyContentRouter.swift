import SwiftUI

struct PrivacyContentRouter: View {
    @ObservedObject var settings: PrivacySettings
    @ObservedObject var capture: WhatsAppWindowCapture

    var body: some View {
        switch settings.renderStyle {
        case .blur:
            BlurOverlayView(intensity: settings.intensity)
        case .pixelate:
            PixelateOverlayView(intensity: settings.intensity, capture: capture)
        case .redact:
            RedactOverlayView(intensity: settings.intensity)
        }
    }
}
