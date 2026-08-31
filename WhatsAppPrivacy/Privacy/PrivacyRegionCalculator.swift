import CoreGraphics

enum PrivacyRegionCalculator {
    /// Default ratio of the chat list sidebar width relative to the overall window width
    static let defaultSidebarRatio: CGFloat = 0.35

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
            // Profile pictures / avatars in sidebar (discrete element boxes if available)
            if options.blurProfilePictures {
                if let avatars = scannedElements?.chatAvatarFrames, !avatars.isEmpty {
                    slices.append(contentsOf: avatars)
                } else {
                    slices.append(CGRect(
                        x: windowFrame.minX + 12,
                        y: windowFrame.minY,
                        width: 52,
                        height: windowFrame.height
                    ))
                }
            }

            // Chat list names (discrete text boxes if available)
            if options.blurChatNames {
                if let names = scannedElements?.chatNameFrames, !names.isEmpty {
                    slices.append(contentsOf: names)
                } else if !options.blurLastMessages {
                    slices.append(CGRect(
                        x: windowFrame.minX + 68,
                        y: windowFrame.minY,
                        width: max(actualSidebarWidth - 140, 0),
                        height: windowFrame.height
                    ))
                }
            }

            // Chat list last message previews (discrete text boxes if available)
            if options.blurLastMessages {
                if let previews = scannedElements?.chatLastMessageFrames, !previews.isEmpty {
                    slices.append(contentsOf: previews)
                } else if !options.blurChatNames {
                    slices.append(CGRect(
                        x: windowFrame.minX + 68,
                        y: windowFrame.minY,
                        width: max(actualSidebarWidth - 85, 0),
                        height: windowFrame.height
                    ))
                }
            }

            // Combined name + last message preview column fallback
            if options.blurChatNames && options.blurLastMessages &&
               (scannedElements?.chatNameFrames.isEmpty ?? true) &&
               (scannedElements?.chatLastMessageFrames.isEmpty ?? true) {
                slices.append(CGRect(
                    x: windowFrame.minX + 68,
                    y: windowFrame.minY,
                    width: max(actualSidebarWidth - 75, 0),
                    height: windowFrame.height
                ))
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
            let headerHeight: CGFloat = 65
            let inputHeight: CGFloat = 60

            // Conversation top header (contact name / avatar / phone)
            if options.blurConversationHeader {
                if let header = scannedElements?.headerFrame {
                    slices.append(header)
                } else {
                    slices.append(CGRect(
                        x: chatOriginX,
                        y: windowFrame.maxY - headerHeight,
                        width: chatWidth,
                        height: headerHeight
                    ))
                }
            }

            // Message composition text input bar at bottom
            if options.blurTextInput {
                if let input = scannedElements?.inputBarFrame {
                    slices.append(input)
                } else {
                    slices.append(CGRect(
                        x: chatOriginX,
                        y: windowFrame.minY,
                        width: chatWidth,
                        height: inputHeight
                    ))
                }
            }

            // Discrete individual message bubbles in chat history
            if options.blurConversationMessages {
                if let bubbles = scannedElements?.messageBubbleFrames, !bubbles.isEmpty {
                    slices.append(contentsOf: bubbles)
                } else {
                    let bottomOffset = options.blurTextInput ? inputHeight : 0
                    let topOffset = options.blurConversationHeader ? headerHeight : 0
                    let middleHeight = max(windowFrame.height - bottomOffset - topOffset, 0)

                    slices.append(CGRect(
                        x: chatOriginX,
                        y: windowFrame.minY + bottomOffset,
                        width: chatWidth,
                        height: middleHeight
                    ))
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
