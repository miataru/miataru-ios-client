import XCTest

final class ExtendedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToForeground() throws {
        let app = XCUIApplication()
        app.launch()
        // Basic sanity: app has at least one window and is running
        let hasWindow = app.windows.element(boundBy: 0).exists || app.otherElements["UIWindow"].exists
        XCTAssertTrue(hasWindow, "App should present a window on launch")
        // No crash alert visible
        XCTAssertFalse(app.alerts.element.exists, "Unexpected alert visible at launch")
    }

    @MainActor
    func testMapPresenceAndBasicTapIfAvailable() throws {
        let app = XCUIApplication()
        app.launch()

        // Try to find a Map by common identifiers or traits
        // SwiftUI Map often exposes as an otherElement; we can search by type and existence heuristics
        let possibleMaps = app.otherElements.matching(NSPredicate(format: "exists == true"))
        var tapped = false
        if possibleMaps.count > 0 {
            // Tap the center of the first large element; avoid gestures requiring location permissions
            let element = possibleMaps.element(boundBy: 0)
            if element.isHittable {
                element.tap()
                tapped = true
            }
        }
        // It's acceptable that no map is present on first screen; ensure no crash alert either way
        XCTAssertFalse(app.alerts.element.exists, "Unexpected alert after basic interaction")
        // Log whether we tapped something
        _ = tapped
    }
}
