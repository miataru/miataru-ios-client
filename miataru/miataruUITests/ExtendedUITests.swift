import XCTest

final class ExtendedUITests: XCTestCase {
    private let baseLaunchArguments = [
        "-ui-testing",
        "-ui-reset-userdefaults",
        "-ui-disable-location-tracking"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchWithCompletedOnboardingShowsRootTabs() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertFalse(app.otherElements["onboarding_container"].exists, "Onboarding should not be shown")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert visible at launch")
    }

    @MainActor
    func testDevicesAddSheetCanOpenAndCancel() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(selectTab(in: app, index: 0, expectedScreenIdentifier: "screen_devices"), "Devices tab should be active")

        let addButton = app.buttons["devices_add_button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Add-device button should exist")
        addButton.tap()

        let cancelButton = app.buttons["add_device_cancel_button"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10), "Add-device sheet should open and show cancel")
        cancelButton.tap()

        XCTAssertTrue(waitForNonExistence(of: cancelButton, timeout: 5), "Add-device sheet should close after cancel")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert after add-device cancel flow")
    }

    @MainActor
    func testSettingsShowOnboardingActionIsReachable() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(selectTab(in: app, index: 2, expectedScreenIdentifier: "screen_settings"), "Settings tab should be active")

        let showOnboardingButton = app.buttons["settings_show_onboarding_again_button"]
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: showOnboardingButton, maxSwipes: 10), "Settings action for onboarding should be available")
        showOnboardingButton.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert after tapping onboarding action")
    }

    @MainActor
    func testQRCodeTabShowsDeviceKeyAction() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(selectTab(in: app, index: 1, expectedScreenIdentifier: "screen_qr"), "QR tab should be active")

        let deviceKeyButton = app.buttons["qr_device_key_button"]
        XCTAssertTrue(deviceKeyButton.waitForExistence(timeout: 10), "Device key button should exist on QR tab")
        if deviceKeyButton.isHittable {
            deviceKeyButton.tap()
        }
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert on QR tab flow")
    }

    @MainActor
    private func launchApp(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseLaunchArguments + extraArguments
        app.launch()
        return app
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForElementByScrollingUp(in app: XCUIApplication, element: XCUIElement, maxSwipes: Int) -> Bool {
        if element.waitForExistence(timeout: 2) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func selectTab(in app: XCUIApplication, index: Int, expectedScreenIdentifier: String) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return false }

        let targetTab = tabBar.buttons.element(boundBy: index)
        guard targetTab.waitForExistence(timeout: 5) else { return false }

        if targetTab.isHittable {
            targetTab.tap()
        }

        return app.otherElements[expectedScreenIdentifier].waitForExistence(timeout: 10)
    }
}
