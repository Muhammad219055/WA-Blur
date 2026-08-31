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
}
