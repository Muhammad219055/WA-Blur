import XCTest
@testable import WhatsAppPrivacy

final class WhatsAppIdentityTests: XCTestCase {
    func test_matchesOfficialBundleIdentifier() {
        let app = RunningAppInfo(bundleIdentifier: "net.whatsapp.WhatsApp", localizedName: "WhatsApp", processIdentifier: 100)
        XCTAssertTrue(WhatsAppIdentity.matches(app))
    }

    func test_doesNotMatchDifferentBundleIdentifier() {
        let app = RunningAppInfo(bundleIdentifier: "com.apple.Safari", localizedName: "Safari", processIdentifier: 101)
        XCTAssertFalse(WhatsAppIdentity.matches(app))
    }

    func test_doesNotMatchOnNameAlone() {
        // A same-named decoy app must not match on localizedName alone --
        // bundle identifier is the only active signal in Phase 1, precisely
        // to avoid this false-positive risk.
        let decoy = RunningAppInfo(bundleIdentifier: "com.example.decoy", localizedName: "WhatsApp", processIdentifier: 102)
        XCTAssertFalse(WhatsAppIdentity.matches(decoy))
    }

    func test_doesNotMatchNilBundleIdentifier() {
        let app = RunningAppInfo(bundleIdentifier: nil, localizedName: "WhatsApp", processIdentifier: 103)
        XCTAssertFalse(WhatsAppIdentity.matches(app))
    }
}
