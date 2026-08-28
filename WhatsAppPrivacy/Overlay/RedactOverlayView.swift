import SwiftUI

struct RedactOverlayView: View {
    let intensity: PrivacyIntensity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(max(intensity.overlayOpacity, 0.85)))
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
