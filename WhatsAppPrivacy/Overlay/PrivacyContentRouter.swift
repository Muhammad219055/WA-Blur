import SwiftUI

struct PrivacyContentRouter: View {
    @ObservedObject var settings: PrivacySettings
    @ObservedObject var revealTracker: OverlayRevealTracker
    var windowFrame: CGRect
    var sidebarWidth: CGFloat?
    var scannedElements: WhatsAppScannedElements? = nil

    var body: some View {
        GranularBlurOverlayView(
            settings: settings,
            windowFrame: windowFrame,
            sidebarWidth: sidebarWidth,
            scannedElements: scannedElements
        )
        .opacity(revealTracker.isPeeking ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: revealTracker.isPeeking)
    }
}
