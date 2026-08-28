import SwiftUI
import AppKit

struct BlurOverlayView: View {
    let intensity: PrivacyIntensity

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.black.opacity(intensity.overlayOpacity)
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        // .behindWindow, not .withinWindow: this is what tells the
        // compositor to blur content from OTHER windows/apps behind this
        // one, not just content within our own view hierarchy.
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
