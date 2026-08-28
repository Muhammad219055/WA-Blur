import SwiftUI

struct PrivacyOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
