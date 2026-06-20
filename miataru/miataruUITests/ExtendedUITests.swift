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
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-initial-tab", "2"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 2).waitForSelected(timeout: 10), "Settings tab should be active")

        let locationDetailsLink = app.descendants(matching: .any)["settings_location_tracking_details_link"].firstMatch
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: locationDetailsLink, maxSwipes: 10), "Location tracking details link should be reachable")
        tapElement(locationDetailsLink)

        let showOnboardingButton = app.buttons["settings_show_onboarding_again_button"]
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: showOnboardingButton, maxSwipes: 4), "Onboarding action should be available on the tracking details screen")
        showOnboardingButton.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert after tapping onboarding action")
    }

    @MainActor
    func testLocationDiagnosticsSheetOpensFromVersionTripleTap() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-initial-tab", "2"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 2).waitForSelected(timeout: 10), "Settings tab should be active")

        let locationDetailsLink = app.descendants(matching: .any)["settings_location_tracking_details_link"].firstMatch
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: locationDetailsLink, maxSwipes: 10), "Location tracking details link should be reachable")
        tapElement(locationDetailsLink)

        let diagnosticsSheet = app.descendants(matching: .any)["location_diagnostics_sheet"].firstMatch
        XCTAssertFalse(diagnosticsSheet.exists, "Location diagnostics sheet should be hidden by default")

        let versionSection = app.descendants(matching: .any)["location_status_version_section"].firstMatch
        XCTAssertTrue(versionSection.waitForExistence(timeout: 10), "Version section should exist on the tracking details screen")
        tripleTapElement(versionSection)

        XCTAssertTrue(diagnosticsSheet.waitForExistence(timeout: 10), "Location diagnostics sheet should open after triple-tapping the version section")
        XCTAssertTrue(app.switches["location_diagnostics_logging_toggle"].waitForExistence(timeout: 5), "Diagnostics logging toggle should be visible in the sheet")

        let doneButton = app.buttons["location_diagnostics_done_button"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Diagnostics sheet should expose a Done button")
        doneButton.tap()
        XCTAssertTrue(waitForNonExistence(of: diagnosticsSheet, timeout: 5), "Location diagnostics sheet should close after tapping Done")
    }

    @MainActor
    func testSettingsAdvancedOptionsNavigationMovesAdvancedControlsOffRootScreen() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-initial-tab", "2"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 2).waitForSelected(timeout: 10), "Settings tab should be active")

        let advancedOptionsLabel = app.staticTexts["settings_advanced_options_label"].firstMatch
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: advancedOptionsLabel, maxSwipes: 6), "Advanced options link should be reachable")

        let pulsingToggle = app.descendants(matching: .any)["settings_pulsing_map_markers_toggle"].firstMatch
        XCTAssertFalse(pulsingToggle.exists, "Advanced-only toggle should not be visible on the root settings screen")

        tapElement(advancedOptionsLabel)

        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: pulsingToggle, maxSwipes: 8), "Moved advanced toggle should be reachable on the advanced options screen")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert after opening advanced options")
    }

    @MainActor
    func testQRCodeTabShowsDeviceKeyAndTrackingPauseActions() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-enable-location-tracking"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(selectTab(in: app, index: 1, expectedScreenIdentifier: "screen_qr"), "QR tab should be active")

        let deviceKeyButton = app.buttons["qr_device_key_button"]
        XCTAssertTrue(deviceKeyButton.waitForExistence(timeout: 10), "Device key button should exist on QR tab")

        let pauseButton = app.buttons["qr_tracking_pause_button"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Server update pause button should exist on QR tab")
        tapElement(pauseButton)
        assertTrackingPauseSheetOptions(in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert on QR tab flow")
    }

    @MainActor
    func testSettingsShowsTrackingPauseEntry() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-enable-location-tracking", "-ui-initial-tab", "2"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 2).waitForSelected(timeout: 10), "Settings tab should be active")

        let pauseEntry = app.descendants(matching: .any)["settings_tracking_pause_button"].firstMatch
        XCTAssertTrue(waitForElementByScrollingUp(in: app, element: pauseEntry, maxSwipes: 4), "Server update pause settings entry should be reachable")
        XCTAssertTrue(app.staticTexts["Temporär keine Server Updates"].exists, "Settings entry should use the renamed title")
        tapElement(pauseEntry)
        assertTrackingPauseSheetOptions(in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Unexpected alert on settings server update pause flow")
    }

    @MainActor
    func testSettingsHidesTrackingPauseEntryWhenServerUpdatesDisabled() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-initial-tab", "2"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(app.tabBars.firstMatch.buttons.element(boundBy: 2).waitForSelected(timeout: 10), "Settings tab should be active")

        let pauseEntry = app.descendants(matching: .any)["settings_tracking_pause_button"].firstMatch
        XCTAssertFalse(pauseEntry.exists, "Server update pause settings entry should be hidden when server updates are disabled")
    }

    @MainActor
    func testDevicesShowsTrackingPauseBannerAndCanResume() throws {
        let app = launchApp(extraArguments: ["-ui-onboarding-completed", "-ui-tracking-pause-active"])

        XCTAssertTrue(app.otherElements["root_tab_view"].waitForExistence(timeout: 10), "Root tab view should be visible")
        XCTAssertTrue(selectTab(in: app, index: 0, expectedScreenIdentifier: "screen_devices"), "Devices tab should be active")

        let banner = app.descendants(matching: .any)["devices_tracking_pause_banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Active server update pause banner should be visible")
        tapElement(banner)

        let resumeButton = app.buttons["tracking_pause_resume_confirmation_button"].firstMatch
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume confirmation button should be visible")
        resumeButton.tap()

        XCTAssertTrue(waitForNonExistence(of: banner, timeout: 5), "Pause banner should disappear after resuming server updates")
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
        if element.waitForExistence(timeout: 2), isVisible(element, in: app) {
            return true
        }

        let scrollContainer: XCUIElement
        if app.collectionViews.firstMatch.exists {
            scrollContainer = app.collectionViews.firstMatch
        } else {
            scrollContainer = app
        }

        for _ in 0..<maxSwipes {
            scrollContainer.swipeUp()
            if element.waitForExistence(timeout: 1), isVisible(element, in: app) {
                return true
            }
        }

        for _ in 0..<(maxSwipes * 2) {
            scrollContainer.swipeDown()
            if element.waitForExistence(timeout: 1), isVisible(element, in: app) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func tapElement(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Element should exist before tapping")

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func isVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }

        let frame = element.frame
        guard frame.width > 0,
              frame.height > 0,
              frame.origin.x.isFinite,
              frame.origin.y.isFinite else {
            return false
        }

        return app.frame.intersects(frame)
    }

    @MainActor
    private func assertTrackingPauseSheetOptions(in app: XCUIApplication) {
        XCTAssertTrue(app.pickers["tracking_pause_days_picker"].waitForExistence(timeout: 5), "Pause days picker should exist")
        XCTAssertTrue(app.pickers["tracking_pause_hours_picker"].waitForExistence(timeout: 5), "Pause hours picker should exist")
        XCTAssertTrue(app.pickers["tracking_pause_minutes_picker"].waitForExistence(timeout: 5), "Pause minutes picker should exist")
        XCTAssertTrue(app.buttons["tracking_pause_start_button"].waitForExistence(timeout: 5), "Pause start button should exist")
    }

    @MainActor
    private func tripleTapElement(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Element should exist before triple-tapping")

        if element.waitForHittable(timeout: 2) {
            element.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            return
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func selectTab(in app: XCUIApplication, index: Int, expectedScreenIdentifier: String) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return false }

        let targetTab = tabBar.buttons.element(boundBy: index)
        guard targetTab.waitForExistence(timeout: 5) else { return false }

        if targetTab.isHittable {
            targetTab.tap()
        } else {
            targetTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        return targetTab.waitForSelected(timeout: 10)
            && app.otherElements[expectedScreenIdentifier].waitForExistence(timeout: 2)
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForSelected(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "selected == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
