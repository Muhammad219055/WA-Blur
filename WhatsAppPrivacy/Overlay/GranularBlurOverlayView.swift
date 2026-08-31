import SwiftUI
import AppKit

struct GranularBlurOverlayView: View {
    @ObservedObject var settings: PrivacySettings
    let windowFrame: CGRect
    let sidebarWidth: CGFloat?

    var body: some View {
        let slices = PrivacyRegionCalculator.granularSlices(
            for: windowFrame,
            options: settings.filterOptions,
            sidebarWidth: sidebarWidth
        )

        ZStack(alignment: .bottomLeading) {
            Color.clear

            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                // Convert Cocoa global screen slice coordinates to local view coordinates
                let localX = slice.minX - windowFrame.minX
                let localY = slice.minY - windowFrame.minY

                Group {
                    switch settings.renderStyle {
                    case .blur:
                        BlurOverlayView(intensity: settings.intensity)
                    case .redact:
                        RedactOverlayView(intensity: settings.intensity)
                    }
                }
                .frame(width: slice.width, height: slice.height)
                .position(x: localX + slice.width / 2, y: windowFrame.height - (localY + slice.height / 2))
            }
        }
        .frame(width: windowFrame.width, height: windowFrame.height)
    }
}
