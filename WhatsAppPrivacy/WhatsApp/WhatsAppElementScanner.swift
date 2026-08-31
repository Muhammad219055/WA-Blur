import AppKit
import ApplicationServices

struct WhatsAppScannedElements: Sendable {
    var chatRowFrames: [CGRect] = []
    var chatNameFrames: [CGRect] = []
    var chatLastMessageFrames: [CGRect] = []
    var chatAvatarFrames: [CGRect] = []
    var messageBubbleFrames: [CGRect] = []
    var mediaFrames: [CGRect] = []
    var headerFrame: CGRect?
    var inputBarFrame: CGRect?
}

enum WhatsAppElementScanner {
    /// Recursively scans the WhatsApp AX hierarchy for discrete chat rows, message bubbles,
    /// avatars, and text elements, returning their frames in Cocoa screen coordinates.
    static func scanElements(forProcessIdentifier pid: pid_t, windowCocoaFrame: CGRect) -> WhatsAppScannedElements {
        guard AXIsProcessTrusted() else { return WhatsAppScannedElements() }

        let appElement = AXUIElementCreateApplication(pid)
        var windowVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowVal) == .success
                || AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowVal) == .success,
              let windowVal,
              CFGetTypeID(windowVal) == AXUIElementGetTypeID() else {
            return WhatsAppScannedElements()
        }

        let windowElement = windowVal as! AXUIElement
        var result = WhatsAppScannedElements()

        // Recursive scan with maximum depth to stay responsive (< 1-2ms)
        scanNode(windowElement, depth: 0, maxDepth: 6, windowCocoaFrame: windowCocoaFrame, result: &result)

        return result
    }

    private static func scanNode(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        windowCocoaFrame: CGRect,
        result: inout WhatsAppScannedElements
    ) {
        if depth > maxDepth { return }

        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = roleVal as? String ?? ""

        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal)

        var axPos = CGPoint.zero
        var axSize = CGSize.zero
        if let posVal { AXValueGetValue(posVal as! AXValue, .cgPoint, &axPos) }
        if let sizeVal { AXValueGetValue(sizeVal as! AXValue, .cgSize, &axSize) }

        if axSize.width > 5 && axSize.height > 5 {
            let axRect = CGRect(origin: axPos, size: axSize)
            if let cocoaRect = AXCoordinateConverter.cocoaFrame(fromAXFrame: axRect) {
                categorizeElement(role: role, element: element, frame: cocoaRect, windowFrame: windowCocoaFrame, result: &result)
            }
        }

        var childrenVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children {
                scanNode(child, depth: depth + 1, maxDepth: maxDepth, windowCocoaFrame: windowCocoaFrame, result: &result)
            }
        }
    }

    private static func categorizeElement(
        role: String,
        element: AXUIElement,
        frame: CGRect,
        windowFrame: CGRect,
        result: inout WhatsAppScannedElements
    ) {
        // Ensure element is strictly inside the WhatsApp window bounds
        guard windowFrame.intersects(frame) else { return }

        // Distinguish sidebar elements vs conversation panel elements
        let sidebarBoundary = windowFrame.minX + max(windowFrame.width * 0.35, 260)
        let isInsideSidebar = frame.maxX <= sidebarBoundary + 30

        if isInsideSidebar {
            // Chat list rows (typically height between 45pt and 100pt, width matching sidebar)
            if (role == "AXRow" || role == "AXCell" || role == "AXGroup") && frame.height >= 45 && frame.height <= 95 && frame.width > 180 {
                result.chatRowFrames.append(frame)
            }
            // Avatar profile pictures (square, ~35-65pt)
            else if (role == "AXImage" || role == "AXButton") && abs(frame.width - frame.height) <= 15 && frame.width >= 30 && frame.width <= 70 {
                result.chatAvatarFrames.append(frame)
            }
            // Text elements (name or message preview)
            else if role == "AXStaticText" && frame.height <= 30 && frame.width > 30 {
                if frame.origin.y > frame.minY + 20 {
                    result.chatNameFrames.append(frame)
                } else {
                    result.chatLastMessageFrames.append(frame)
                }
            }
        } else {
            // Conversation panel elements
            // Header bar at top of chat
            if frame.maxY >= windowFrame.maxY - 10 && frame.height >= 40 && frame.height <= 90 {
                result.headerFrame = frame
            }
            // Message input field at bottom
            else if frame.minY <= windowFrame.minY + 15 && frame.height >= 35 && frame.height <= 80 {
                result.inputBarFrame = frame
            }
            // Message bubble items (groups or cells with reasonable bubble dimensions)
            else if (role == "AXRow" || role == "AXCell" || role == "AXGroup" || role == "AXStaticText") &&
                    frame.height >= 20 && frame.height < windowFrame.height * 0.7 &&
                    frame.width >= 40 && frame.width <= windowFrame.width * 0.75 {
                result.messageBubbleFrames.append(frame)
            }
            // Media previews in conversation
            else if role == "AXImage" && frame.height >= 80 && frame.width >= 80 {
                result.mediaFrames.append(frame)
            }
        }
    }
}
