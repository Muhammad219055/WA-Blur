import XCTest
@testable import WhatsAppPrivacy

final class PrivacySettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #file)
        defaults.removePersistentDomain(forName: #file)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: #file)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func test_defaultsToBlurAndMedium_whenNothingStored() {
        let settings = PrivacySettings(defaults: defaults)
        XCTAssertEqual(settings.renderStyle, .blur)
        XCTAssertEqual(settings.intensity, .medium)
    }

    @MainActor
    func test_persistsRenderStyleAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.renderStyle = .pixelate

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.renderStyle, .pixelate)
    }

    @MainActor
    func test_persistsIntensityAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.intensity = .high

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.intensity, .high)
    }

    @MainActor
    func test_defaultsToFullWindowAndNone_forRegionAndReveal() {
        let settings = PrivacySettings(defaults: defaults)
        XCTAssertEqual(settings.regionScope, .fullWindow)
        XCTAssertEqual(settings.revealMode, .none)
    }

    @MainActor
    func test_persistsRegionScopeAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.regionScope = .sidebarOnly

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.regionScope, .sidebarOnly)
    }

    @MainActor
    func test_persistsRevealModeAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.revealMode = .hoverPeek

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.revealMode, .hoverPeek)
    }

    func test_intensity_overlayOpacityIncreasesWithLevel() {
        XCTAssertLessThan(PrivacyIntensity.low.overlayOpacity, PrivacyIntensity.medium.overlayOpacity)
        XCTAssertLessThan(PrivacyIntensity.medium.overlayOpacity, PrivacyIntensity.high.overlayOpacity)
    }
}
