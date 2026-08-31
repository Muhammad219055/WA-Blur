import SwiftUI

struct PrivacyContentRouter: View {
    @ObservedObject var settings: PrivacySettings
    @ObservedObject var revealTracker: OverlayRevealTracker

    var body: some View {
        Group {
            switch settings.renderStyle {
            case .blur:
                BlurOverlayView(intensity: settings.intensity)
            case .redact:
                RedactOverlayView(intensity: settings.intensity)
            }
        }
        .opacity(revealTracker.isPeeking ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: revealTracker.isPeeking)
    }
}
