import CoreGraphics

enum PrivacyRegionCalculator {
    /// Default ratio of the chat list sidebar width relative to the overall window width
    static let defaultSidebarRatio: CGFloat = 0.35

    /// Computes the sub-frame inside a Cocoa-coordinate window frame for a given region scope.
    /// In Cocoa coordinates:
    /// - (minX, minY) is the bottom-left corner of the window.
    /// - sidebar occupies the leftmost horizontal slice: [minX ..< minX + sidebarWidth]
    /// - chat area occupies the remaining horizontal slice: [minX + sidebarWidth ..< maxX]
    static func regionFrame(
        for windowFrame: CGRect,
        scope: PrivacyRegionScope,
        sidebarRatio: CGFloat = defaultSidebarRatio
    ) -> CGRect {
        guard !windowFrame.isEmpty && !windowFrame.isNull else { return windowFrame }

        switch scope {
        case .fullWindow:
            return windowFrame

        case .sidebarOnly:
            let sidebarWidth = max(min(windowFrame.width * sidebarRatio, windowFrame.width), 0)
            return CGRect(
                x: windowFrame.minX,
                y: windowFrame.minY,
                width: sidebarWidth,
                height: windowFrame.height
            )

        case .chatOnly:
            let sidebarWidth = max(min(windowFrame.width * sidebarRatio, windowFrame.width), 0)
            let chatWidth = max(windowFrame.width - sidebarWidth, 0)
            return CGRect(
                x: windowFrame.minX + sidebarWidth,
                y: windowFrame.minY,
                width: chatWidth,
                height: windowFrame.height
            )
        }
    }
}
