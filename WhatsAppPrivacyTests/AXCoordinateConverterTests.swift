import XCTest
@testable import WhatsAppPrivacy

final class AXCoordinateConverterTests: XCTestCase {
    func test_primaryScreenOnly_topLeftWindow() {
        let axFrame = CGRect(x: 100, y: 50, width: 800, height: 600)
        let result = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        XCTAssertEqual(result, CGRect(x: 100, y: 430, width: 800, height: 600))
    }

    func test_windowAtAXOrigin_sitsAtTopOfCocoaSpace() {
        let axFrame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let result = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        XCTAssertEqual(result, CGRect(x: 0, y: 780, width: 400, height: 300))
    }

    func test_negativeAXOrigin_secondaryDisplayToTheLeft() {
        // Window mostly on a secondary display positioned to the left of the
        // primary display. X carries straight through unchanged in both spaces.
        let axFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let result = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        XCTAssertEqual(result, CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    }

    func test_windowBelowPrimaryScreenBounds_onDisplayMountedBelow() {
        // A window on a secondary display physically arranged below the
        // primary display has an AX y greater than the primary screen's
        // height; the flip still applies uniformly, producing a negative
        // Cocoa y -- correct, since Cocoa y is negative below the primary
        // screen's origin.
        let axFrame = CGRect(x: 0, y: 1200, width: 1920, height: 1080)
        let result = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        XCTAssertEqual(result, CGRect(x: 0, y: -1200, width: 1920, height: 1080))
    }

    func test_deterministic_forFixedInputs() {
        let axFrame = CGRect(x: 300, y: 100, width: 640, height: 480)
        let resultA = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        let resultB = AXCoordinateConverter.cocoaFrame(fromAXFrame: axFrame, primaryScreenHeight: 1080)
        XCTAssertEqual(resultA, resultB)
        XCTAssertEqual(resultA, CGRect(x: 300, y: 500, width: 640, height: 480))
    }

    func test_screensOverload_returnsNilWhenNoScreens() {
        XCTAssertNil(AXCoordinateConverter.cocoaFrame(fromAXFrame: .zero, screens: []))
    }
}
