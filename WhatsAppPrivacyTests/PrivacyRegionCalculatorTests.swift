import XCTest
@testable import WhatsAppPrivacy

final class PrivacyRegionCalculatorTests: XCTestCase {
    private let baseFrame = CGRect(x: 100, y: 100, width: 1000, height: 600)

    func test_fullWindowScope_returnsExactBaseFrame() {
        let frame = PrivacyRegionCalculator.regionFrame(for: baseFrame, scope: .fullWindow)
        XCTAssertEqual(frame, baseFrame)
    }

    func test_sidebarOnlyScope_returnsLeftSegment() {
        let frame = PrivacyRegionCalculator.regionFrame(for: baseFrame, scope: .sidebarOnly, sidebarRatio: 0.35)
        XCTAssertEqual(frame.origin.x, 100)
        XCTAssertEqual(frame.origin.y, 100)
        XCTAssertEqual(frame.size.width, 350)
        XCTAssertEqual(frame.size.height, 600)
    }

    func test_chatOnlyScope_returnsRightSegment() {
        let frame = PrivacyRegionCalculator.regionFrame(for: baseFrame, scope: .chatOnly, sidebarRatio: 0.35)
        XCTAssertEqual(frame.origin.x, 450) // 100 + 350
        XCTAssertEqual(frame.origin.y, 100)
        XCTAssertEqual(frame.size.width, 650) // 1000 - 350
        XCTAssertEqual(frame.size.height, 600)
    }

    func test_sidebarWidthClamping_boundsSmallAndLargeWindows() {
        let narrowFrame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let sidebarNarrow = PrivacyRegionCalculator.regionFrame(for: narrowFrame, scope: .sidebarOnly, sidebarRatio: 0.35)
        // Ensure sidebar does not exceed total width
        XCTAssertLessThanOrEqual(sidebarNarrow.size.width, narrowFrame.size.width)
        XCTAssertGreaterThan(sidebarNarrow.size.width, 0)
    }

    func test_sidebarAndChatUnion_matchesFullWindow() {
        let sidebar = PrivacyRegionCalculator.regionFrame(for: baseFrame, scope: .sidebarOnly, sidebarRatio: 0.35)
        let chat = PrivacyRegionCalculator.regionFrame(for: baseFrame, scope: .chatOnly, sidebarRatio: 0.35)

        XCTAssertEqual(sidebar.union(chat), baseFrame)
        XCTAssertEqual(sidebar.width + chat.width, baseFrame.width)
    }

    func test_granularSlices_everything_returnsSingleFullWindowSlice() {
        let slices = PrivacyRegionCalculator.granularSlices(for: baseFrame, options: .everything, sidebarWidth: 350)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first, baseFrame)
    }

    func test_granularSlices_chatListOnly_returnsSidebarSlice() {
        let slices = PrivacyRegionCalculator.granularSlices(for: baseFrame, options: .chatListOnly, sidebarWidth: 350)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices.first?.width, 350)
        XCTAssertEqual(slices.first?.origin.x, 100)
    }

    func test_granularSlices_individualToggles_returnsSpecificSubframes() {
        var options = PrivacyFilterOptions()
        options.blurChatNames = false
        options.blurLastMessages = false
        options.blurProfilePictures = true // avatar column
        options.blurConversationHeader = true // top header
        options.blurConversationMessages = false
        options.blurConversationMedia = false
        options.blurTextInput = true // bottom input

        let slices = PrivacyRegionCalculator.granularSlices(for: baseFrame, options: options, sidebarWidth: 350)
        XCTAssertEqual(slices.count, 3) // avatar column + header + text input

        // Header slice should be at the top of the chat panel
        let headerSlice = slices.first { $0.height == 65 }
        XCTAssertNotNil(headerSlice)
        XCTAssertEqual(headerSlice?.origin.x, 450) // 100 + 350

        // Input slice should be at the bottom of the chat panel
        let inputSlice = slices.first { $0.height == 60 }
        XCTAssertNotNil(inputSlice)
        XCTAssertEqual(inputSlice?.origin.x, 450)
        XCTAssertEqual(inputSlice?.origin.y, 100)
    }
}
