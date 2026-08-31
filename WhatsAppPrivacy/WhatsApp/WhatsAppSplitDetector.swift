import AppKit
import ApplicationServices

enum WhatsAppSplitDetector {
    /// Inspects the live AX element tree of the WhatsApp process to detect
    /// the real-time width of the resizable left sidebar pane.
    static func detectSidebarWidth(forProcessIdentifier pid: pid_t) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)
        var windowVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowVal) == .success
                || AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowVal) == .success,
              let windowVal,
              CFGetTypeID(windowVal) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowElement = windowVal as! AXUIElement

        var childrenVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement], !children.isEmpty else {
            return nil
        }

        // Traverse first level of split groups or direct columns
        for child in children {
            var roleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleVal)
            let role = roleVal as? String ?? ""

            if role == "AXSplitGroup" || role == "AXGroup" {
                var subChildrenVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &subChildrenVal) == .success,
                   let subChildren = subChildrenVal as? [AXUIElement], subChildren.count >= 2 {
                    // First child in split group is the sidebar
                    var sizeVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(subChildren[0], kAXSizeAttribute as CFString, &sizeVal) == .success,
                       let sizeVal {
                        var size = CGSize.zero
                        if AXValueGetValue(sizeVal as! AXValue, .cgSize, &size), size.width > 150 && size.width < 800 {
                            return size.width
                        }
                    }
                }
            }

            // Check if child itself is the sidebar
            var sizeVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let sizeVal {
                var size = CGSize.zero
                if AXValueGetValue(sizeVal as! AXValue, .cgSize, &size), size.width > 200 && size.width < 600 {
                    return size.width
                }
            }
        }

        return nil
    }
}
