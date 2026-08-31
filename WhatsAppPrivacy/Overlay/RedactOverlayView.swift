import SwiftUI

struct RedactOverlayView: View {
    let intensity: PrivacyIntensity

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(max(intensity.overlayOpacity, 0.90)))
    }
}
