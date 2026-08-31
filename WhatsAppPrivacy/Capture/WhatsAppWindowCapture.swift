import ScreenCaptureKit
import CoreImage
import CoreMedia

@MainActor
final class WhatsAppWindowCapture: NSObject, ObservableObject {
    @Published private(set) var latestFrame: CGImage?

    private var stream: SCStream?
    private let ciContext = CIContext()

    func startCapture(forProcessIdentifier pid: pid_t) async {
        stopCapture()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let matchingWindows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.frame.width > 100 && $0.frame.height > 100
            }
            guard let scWindow = matchingWindows.max(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            }) ?? content.windows.first(where: { $0.owningApplication?.processID == pid }) else {
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = max(Int(scWindow.frame.width), 1)
            config.height = max(Int(scWindow.frame.height), 1)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            config.showsCursor = false

            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            latestFrame = nil
        }
    }

    func stopCapture() {
        let streamToStop = stream
        stream = nil
        latestFrame = nil
        Task {
            try? await streamToStop?.stopCapture()
        }
    }
}

extension WhatsAppWindowCapture: SCStreamOutput {
    // Not @MainActor-isolated like the rest of this class: SCStreamOutput's
    // requirement is declared nonisolated in ScreenCaptureKit, so conforming
    // from a @MainActor class means this one method opts out and hops back
    // to the main actor explicitly to touch `latestFrame` -- the same
    // pattern the Phase 1 AX observer callback uses for the same reason.
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        Task { @MainActor in
            self.latestFrame = cgImage
        }
    }
}
