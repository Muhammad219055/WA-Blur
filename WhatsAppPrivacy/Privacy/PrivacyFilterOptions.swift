import Foundation

struct PrivacyFilterOptions: Codable, Sendable, Equatable {
    var blurChatNames: Bool = true
    var blurLastMessages: Bool = true
    var blurProfilePictures: Bool = true
    var blurConversationHeader: Bool = true
    var blurConversationMessages: Bool = true
    var blurConversationMedia: Bool = true
    var blurTextInput: Bool = true

    var isEverythingBlurred: Bool {
        blurChatNames && blurLastMessages && blurProfilePictures &&
        blurConversationHeader && blurConversationMessages && blurConversationMedia && blurTextInput
    }

    var isChatListFullyBlurred: Bool {
        blurChatNames && blurLastMessages && blurProfilePictures
    }

    var isConversationFullyBlurred: Bool {
        blurConversationHeader && blurConversationMessages && blurConversationMedia && blurTextInput
    }

    static var everything: PrivacyFilterOptions {
        PrivacyFilterOptions(
            blurChatNames: true,
            blurLastMessages: true,
            blurProfilePictures: true,
            blurConversationHeader: true,
            blurConversationMessages: true,
            blurConversationMedia: true,
            blurTextInput: true
        )
    }

    static var chatListOnly: PrivacyFilterOptions {
        PrivacyFilterOptions(
            blurChatNames: true,
            blurLastMessages: true,
            blurProfilePictures: true,
            blurConversationHeader: false,
            blurConversationMessages: false,
            blurConversationMedia: false,
            blurTextInput: false
        )
    }

    static var conversationOnly: PrivacyFilterOptions {
        PrivacyFilterOptions(
            blurChatNames: false,
            blurLastMessages: false,
            blurProfilePictures: false,
            blurConversationHeader: true,
            blurConversationMessages: true,
            blurConversationMedia: true,
            blurTextInput: true
        )
    }
}
