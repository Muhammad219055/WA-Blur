import SwiftUI

struct PrivacyContentRouter: View {
    @ObservedObject var settings: PrivacySettings
    @ObservedObject var revealTracker: OverlayRevealTracker
    var windowFrame: CGRect
    var sidebarWidth: CGFloat?

    var body: some View {
        GranularBlurOverlayView(
            settings: settings,
            windowFrame: windowFrame,
            sidebarWidth: sidebarWidth
        )
        .opacity(revealTracker.isPeeking ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: revealTracker.isPeeking)
    }
}
