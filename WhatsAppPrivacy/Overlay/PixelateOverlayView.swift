import SwiftUI
import CoreImage

struct PixelateOverlayView: View {
    let intensity: PrivacyIntensity
    @ObservedObject var capture: WhatsAppWindowCapture

    private let ciContext = CIContext()

    var body: some View {
        ZStack {
            if let pixelated = pixelatedImage {
                Image(decorative: pixelated, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            Color.black.opacity(intensity.overlayOpacity)
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .clipped()
    }

    private var pixelatedImage: CGImage? {
        guard let frame = capture.latestFrame else { return nil }
        let ciImage = CIImage(cgImage: frame)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blockScale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: ciImage.extent)
    }

    private var blockScale: CGFloat {
        switch intensity {
        case .low: return 12
        case .medium: return 20
        case .high: return 32
        }
    }
}
