import SwiftUI
import AppKit

struct GranularBlurOverlayView: View {
    @ObservedObject var settings: PrivacySettings
    let windowFrame: CGRect
    let sidebarWidth: CGFloat?
    var scannedElements: WhatsAppScannedElements? = nil

    var body: some View {
        let slices = PrivacyRegionCalculator.granularSlices(
            for: windowFrame,
            options: settings.filterOptions,
            sidebarWidth: sidebarWidth,
            scannedElements: scannedElements
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
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius(for: slice), style: .continuous))
                .offset(x: localX, y: localYFromTop)
            }
        }
        .frame(width: windowFrame.width, height: windowFrame.height)
        .clipped()
    }

    private func cornerRadius(for slice: CGRect) -> CGFloat {
        if slice.width == 48 && slice.height == 48 {
            return 24 // circular avatar
        } else if slice.height <= 24 {
            return 6 // pill for name / message preview
        } else if slice.width < windowFrame.width * 0.85 && slice.height < windowFrame.height * 0.85 {
            return 12 // rounded message bubble / card
        } else {
            return 0
        }
    }
}
