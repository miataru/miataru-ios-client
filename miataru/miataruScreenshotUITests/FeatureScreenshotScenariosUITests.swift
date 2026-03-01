import XCTest

final class FeatureScreenshotScenariosUITests: ScreenshotBaseUITestCase {
    @MainActor
    func test_01_root_devices() throws {
        launchApp(onboardingCompleted: true, initialTab: 0, scenarioID: "root-devices")
        let visible = app.otherElements["screen_devices"].waitForExistence(timeout: 10)
            || app.otherElements["screen_devices_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(visible, "Devices screen is not available")
        captureScenarioScreenshot(index: 1, slug: "root-devices")
    }

    @MainActor
    func test_02_root_qr() throws {
        launchApp(onboardingCompleted: true, initialTab: 1, scenarioID: "root-qr")
        let qrVisible = app.otherElements["screen_qr"].waitForExistence(timeout: 10)
            || app.otherElements["screen_qr_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(qrVisible, "QR screen is not available")
        captureScenarioScreenshot(index: 2, slug: "root-qr")
    }

    @MainActor
    func test_03_root_settings() throws {
        launchApp(onboardingCompleted: true, initialTab: 2, scenarioID: "root-settings")
        let iPhoneSettings = app.otherElements["screen_settings"].waitForExistence(timeout: 10)
        let iPadSettings = app.otherElements["screen_settings_ipad"].waitForExistence(timeout: 10)
            || selectTab(index: 3, expectedIdentifier: "screen_settings_ipad")
        try skipIfFalse(iPhoneSettings || iPadSettings, "Settings screen is not available")
        captureScenarioScreenshot(index: 3, slug: "root-settings")
    }

    @MainActor
    func test_04_devices_add_sheet() throws {
        launchApp(onboardingCompleted: true, initialTab: 0, scenarioID: "devices-add-sheet")
        let visible = app.otherElements["screen_devices"].waitForExistence(timeout: 10)
            || app.otherElements["screen_devices_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(visible, "Devices screen is not available")

        let addButton = app.buttons["devices_add_button"]
        try skipIfFalse(addButton.waitForExistence(timeout: 8), "Add-device button is missing")
        addButton.tap()

        let cancelButton = app.buttons["add_device_cancel_button"]
        try skipIfFalse(cancelButton.waitForExistence(timeout: 8), "Add-device sheet did not open")
        captureScenarioScreenshot(index: 4, slug: "devices-add-sheet")

        cancelButton.tap()
        _ = waitForNonExistence(of: cancelButton, timeout: 4)
    }

    @MainActor
    func test_05_settings_show_onboarding_action() throws {
        launchApp(onboardingCompleted: true, initialTab: 2, scenarioID: "settings-show-onboarding")

        let settingsVisible = app.otherElements["screen_settings"].waitForExistence(timeout: 10)
            || app.otherElements["screen_settings_ipad"].waitForExistence(timeout: 10)
            || selectTab(index: 3, expectedIdentifier: "screen_settings_ipad")
        try skipIfFalse(settingsVisible, "Settings screen is not visible")

        let showOnboardingButton = app.buttons["settings_show_onboarding_again_button"]
        try skipIfFalse(waitForElementByScrollingUp(in: app, element: showOnboardingButton, maxSwipes: 10), "Settings onboarding action not found")
        captureScenarioScreenshot(index: 5, slug: "settings-show-onboarding")
    }

    @MainActor
    func test_06_onboarding_start() throws {
        launchApp(onboardingCompleted: false, scenarioID: "onboarding-start")
        let onboardingVisible = ensureOnboardingVisibleOrPresentFromSettings()
        XCTAssertTrue(onboardingVisible, "Onboarding container is not visible")
        guard onboardingVisible else { return }
        captureScenarioScreenshot(index: 6, slug: "onboarding-step-01")
    }

    @MainActor
    func test_07_onboarding_pager() throws {
        launchApp(onboardingCompleted: false, scenarioID: "onboarding-pager")
        let onboardingVisible = ensureOnboardingVisibleOrPresentFromSettings()
        XCTAssertTrue(onboardingVisible, "Onboarding container is not visible")
        guard onboardingVisible else { return }

        advanceOnboardingPagerOneStep()
        let reachedSecondPage = waitForOnboardingPage(target: 2, timeout: 6)
        XCTAssertTrue(reachedSecondPage, "Could not advance onboarding pager to page 2")
        guard reachedSecondPage else { return }

        captureScenarioScreenshot(index: 72, slug: "onboarding-step-02")

        guard let pageState = onboardingPageState() else {
            XCTFail("Unable to determine onboarding page progress")
            return
        }

        var currentPage = pageState.current
        let totalPages = pageState.total
        while currentPage < totalPages {
            let nextPage = currentPage + 1
            advanceOnboardingPagerOneStep()
            let advanced = waitForOnboardingPage(target: nextPage, timeout: 6)
            XCTAssertTrue(advanced, "Could not advance onboarding pager to page \(nextPage)")
            guard advanced else { break }
            currentPage = nextPage

            let pageSlug = String(format: "onboarding-step-%02d", currentPage)
            let pageIndex = 70 + currentPage
            captureScenarioScreenshot(index: pageIndex, slug: pageSlug)
        }
    }

    @MainActor
    func test_08_qr_device_key_action() throws {
        launchApp(onboardingCompleted: true, initialTab: 1, scenarioID: "qr-device-key")
        let qrVisible = app.otherElements["screen_qr"].waitForExistence(timeout: 10)
            || app.otherElements["screen_qr_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(qrVisible, "QR screen is not visible")

        let deviceKeyButton = app.buttons["qr_device_key_button"]
        try skipIfFalse(deviceKeyButton.waitForExistence(timeout: 8), "Device key action not found")
        deviceKeyButton.tap()
        let sheetVisible = waitForAnyElement(identifier: "device_key_sheet", timeout: 8)
        XCTAssertTrue(sheetVisible, "Device key sheet did not open")
        guard sheetVisible else { return }
        captureScenarioScreenshot(index: 8, slug: "qr-device-key")
    }

    @MainActor
    func test_09_ipad_groups_tab_or_skip() throws {
        launchApp(onboardingCompleted: true, initialTab: 1, scenarioID: "groups-tab")

        if app.otherElements["screen_groups_ipad"].waitForExistence(timeout: 8) || selectTab(index: 1, expectedIdentifier: "screen_groups_ipad") {
            captureScenarioScreenshot(index: 9, slug: "groups-tab")
            return
        }

        throw XCTSkip("Groups tab scenario applies to iPad layout only")
    }

    @MainActor
    func test_10_settings_navigation_container() throws {
        launchApp(onboardingCompleted: true, initialTab: 2, scenarioID: "settings-navigation")

        let settingsVisible = waitForAnyElement(identifier: "screen_settings", timeout: 10)
            || waitForAnyElement(identifier: "screen_settings_ipad", timeout: 10)
            || selectTab(index: 2, expectedIdentifier: "screen_settings")
            || selectTab(index: 3, expectedIdentifier: "screen_settings_ipad")
        XCTAssertTrue(settingsVisible, "Settings screen is not reachable")
        guard settingsVisible else { return }

        // Move down into the navigation section so this scenario is distinct from root settings.
        app.swipeUp()
        captureScenarioScreenshot(index: 10, slug: "settings-navigation")
    }

    @MainActor
    func test_11_device_map_overview() throws {
        launchApp(onboardingCompleted: true, initialTab: 0, scenarioID: "device-map-overview")
        let devicesVisible = waitForAnyElement(identifier: "screen_devices", timeout: 10)
            || waitForAnyElement(identifier: "screen_devices_ipad", timeout: 10)
        try skipIfFalse(devicesVisible, "Devices screen is not available")

        let thisDeviceRow = app.descendants(matching: .any)["devices_row_this_device"].firstMatch
        try skipIfFalse(thisDeviceRow.waitForExistence(timeout: 8), "This device row not found")
        thisDeviceRow.tap()

        let mapVisible = waitForAnyElement(identifier: "device_map_overview", timeout: 10)
        try skipIfFalse(mapVisible, "Device map overview is not visible")
        captureScenarioScreenshot(index: 11, slug: "device-map-overview")
    }

    @MainActor
    private func ensureOnboardingVisibleOrPresentFromSettings() -> Bool {
        if waitForOnboardingContainer(timeout: 8) {
            return true
        }

        let settingsVisible = waitForAnyElement(identifier: "screen_settings", timeout: 8)
            || waitForAnyElement(identifier: "screen_settings_ipad", timeout: 8)
            || selectTab(index: 2, expectedIdentifier: "screen_settings")
            || selectTab(index: 3, expectedIdentifier: "screen_settings_ipad")
        guard settingsVisible else { return false }

        let showOnboardingButton = app.buttons["settings_show_onboarding_again_button"]
        guard waitForElementByScrollingUp(in: app, element: showOnboardingButton, maxSwipes: 12) else { return false }
        showOnboardingButton.tap()

        return waitForOnboardingContainer(timeout: 10)
    }

    @MainActor
    private func waitForOnboardingContainer(timeout: TimeInterval) -> Bool {
        waitForAnyElement(identifier: "onboarding_container", timeout: timeout)
            || waitForAnyElement(identifier: "onboarding_container_ipad", timeout: timeout)
    }

    @MainActor
    private func advanceOnboardingPagerOneStep() {
        let iPhoneContainer = app.descendants(matching: .any)["onboarding_container"].firstMatch
        if iPhoneContainer.exists {
            iPhoneContainer.swipeLeft()
            return
        }

        let iPadContainer = app.descendants(matching: .any)["onboarding_container_ipad"].firstMatch
        if iPadContainer.exists {
            iPadContainer.swipeLeft()
        }
    }

    @MainActor
    private func waitForAnyElement(identifier: String, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func onboardingPageState(timeout: TimeInterval = 2) -> (current: Int, total: Int)? {
        let iPhoneIndicator = app.pageIndicators["onboarding_container"]
        if iPhoneIndicator.waitForExistence(timeout: timeout),
           let parsed = parsePageState(from: iPhoneIndicator) {
            return parsed
        }

        let iPadIndicator = app.pageIndicators["onboarding_container_ipad"]
        if iPadIndicator.waitForExistence(timeout: timeout),
           let parsed = parsePageState(from: iPadIndicator) {
            return parsed
        }

        let fallback = app.pageIndicators.firstMatch
        if fallback.waitForExistence(timeout: timeout),
           let parsed = parsePageState(from: fallback) {
            return parsed
        }

        return nil
    }

    @MainActor
    private func waitForOnboardingPage(target: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let state = onboardingPageState(timeout: 0.2), state.current == target {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func parsePageState(from indicator: XCUIElement) -> (current: Int, total: Int)? {
        guard let value = indicator.value as? String else { return nil }
        let numbers = value
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}
