import CoreGraphics

enum PrivacyRegionCalculator {
    /// Default ratio of the chat list sidebar width relative to the overall window width
    static let defaultSidebarRatio: CGFloat = 0.35
    static let chatRowHeight: CGFloat = 72.0
    static let navRailWidth: CGFloat = 60.0
    static let sidebarHeaderHeight: CGFloat = 108.0

    /// Computes the sub-frame inside a Cocoa-coordinate window frame for a given region scope.
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

        case .custom:
            return windowFrame
        }
    }

    /// Computes discrete granular sub-frame slices (in Cocoa screen coordinates)
    /// based on the enabled privacy filter options, dynamic sidebar width, and scanned AX elements.
    static func granularSlices(
        for windowFrame: CGRect,
        options: PrivacyFilterOptions,
        sidebarWidth: CGFloat? = nil,
        scannedElements: WhatsAppScannedElements? = nil
    ) -> [CGRect] {
        guard !windowFrame.isEmpty && !windowFrame.isNull else { return [] }

        if options.isEverythingBlurred {
            return [windowFrame]
        }

        let actualSidebarWidth = max(min(sidebarWidth ?? (windowFrame.width * defaultSidebarRatio), windowFrame.width), 0)
        let chatWidth = max(windowFrame.width - actualSidebarWidth, 0)
        let chatOriginX = windowFrame.minX + actualSidebarWidth

        var slices: [CGRect] = []

        // MARK: - Sidebar Granular Slices
        if options.isChatListFullyBlurred {
            slices.append(CGRect(
                x: windowFrame.minX,
                y: windowFrame.minY,
                width: actualSidebarWidth,
                height: windowFrame.height
            ))
        } else {
            // Determine all visible chat row Y coordinates
            let chatListTop = windowFrame.maxY - sidebarHeaderHeight
            var rowTop = chatListTop

            let textX = windowFrame.minX + navRailWidth + 64 // Right after avatar
            let nameWidth = max(actualSidebarWidth - (navRailWidth + 64 + 75), 100)
            let previewWidth = max(actualSidebarWidth - (navRailWidth + 64 + 40), 120)
            let avatarX = windowFrame.minX + navRailWidth + 8

            while rowTop > windowFrame.minY + 20 {
                let rowBottom = max(rowTop - chatRowHeight, windowFrame.minY)

                // 1. Discrete Avatar Circle for each chat row
                if options.blurProfilePictures {
                    slices.append(CGRect(
                        x: avatarX,
                        y: rowTop - 58,
                        width: 48,
                        height: 48
                    ))
                }

                // 2. Discrete Contact Name Badge for each chat row
                if options.blurChatNames {
                    slices.append(CGRect(
                        x: textX,
                        y: rowTop - 30,
                        width: nameWidth,
                        height: 18
                    ))
                }

                // 3. Discrete Last Message Preview for each chat row
                if options.blurLastMessages {
                    slices.append(CGRect(
                        x: textX,
                        y: rowTop - 54,
                        width: previewWidth,
                        height: 16
                    ))
                }

                rowTop -= chatRowHeight
            }
        }

        // MARK: - Active Conversation Granular Slices
        if options.isConversationFullyBlurred {
            slices.append(CGRect(
                x: chatOriginX,
                y: windowFrame.minY,
                width: chatWidth,
                height: windowFrame.height
            ))
        } else {
            let headerHeight: CGFloat = 60
            let inputHeight: CGFloat = 60

            // Conversation top header (contact name / avatar / phone)
            if options.blurConversationHeader {
                slices.append(CGRect(
                    x: chatOriginX,
                    y: windowFrame.maxY - headerHeight,
                    width: chatWidth,
                    height: headerHeight
                ))
            }

            // Message composition text input bar at bottom
            if options.blurTextInput {
                slices.append(CGRect(
                    x: chatOriginX,
                    y: windowFrame.minY,
                    width: chatWidth,
                    height: inputHeight
                ))
            }

            // Discrete individual message bubbles in chat history
            if options.blurConversationMessages {
                if let bubbles = scannedElements?.messageBubbleFrames, !bubbles.isEmpty {
                    slices.append(contentsOf: bubbles)
                } else {
                    // Staggered discrete message bubble cards in the conversation view
                    let bottomY = windowFrame.minY + inputHeight + 20
                    let topY = windowFrame.maxY - headerHeight - 20
                    var currentY = bottomY
                    var isIncoming = true

                    while currentY < topY - 40 {
                        let bubbleWidth: CGFloat = min(max(chatWidth * 0.45, 180), 320)
                        let bubbleHeight: CGFloat = 46
                        let bubbleX = isIncoming ? (chatOriginX + 30) : (windowFrame.maxX - bubbleWidth - 30)

                        slices.append(CGRect(
                            x: bubbleX,
                            y: currentY,
                            width: bubbleWidth,
                            height: bubbleHeight
                        ))

                        currentY += bubbleHeight + 16
                        isIncoming.toggle()
                    }
                }
            }

            // Discrete media previews in conversation
            if options.blurConversationMedia {
                if let media = scannedElements?.mediaFrames, !media.isEmpty {
                    slices.append(contentsOf: media)
                }
            }
        }

        return slices
    }
}
