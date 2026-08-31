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

        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                let localX = slice.minX - windowFrame.minX
                let localYFromBottom = slice.minY - windowFrame.minY
                let localYFromTop = windowFrame.height - localYFromBottom - slice.height

                Group {
                    switch settings.renderStyle {
                    case .blur:
                        BlurOverlayView(intensity: settings.intensity)
                    case .redact:
                        RedactOverlayView(intensity: settings.intensity)
                    }
                }
                .frame(width: slice.width, height: slice.height)
                .offset(x: localX, y: localYFromTop)
            }
        }
        .frame(width: windowFrame.width, height: windowFrame.height)
        .clipped()
    }
}
