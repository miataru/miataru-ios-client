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
        let onboardingVisible = app.otherElements["onboarding_container"].waitForExistence(timeout: 10)
            || app.otherElements["onboarding_container_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(onboardingVisible, "Onboarding container is not visible")
        captureScenarioScreenshot(index: 6, slug: "onboarding-start")
    }

    @MainActor
    func test_07_onboarding_pager() throws {
        launchApp(onboardingCompleted: false, scenarioID: "onboarding-pager")
        let pagerVisible = app.otherElements["onboarding_pager"].waitForExistence(timeout: 10)
            || app.otherElements["onboarding_pager_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(pagerVisible, "Onboarding pager is not visible")
        captureScenarioScreenshot(index: 7, slug: "onboarding-pager")
    }

    @MainActor
    func test_08_qr_device_key_action() throws {
        launchApp(onboardingCompleted: true, initialTab: 1, scenarioID: "qr-device-key")
        let qrVisible = app.otherElements["screen_qr"].waitForExistence(timeout: 10)
            || app.otherElements["screen_qr_ipad"].waitForExistence(timeout: 10)
        try skipIfFalse(qrVisible, "QR screen is not visible")

        let deviceKeyButton = app.buttons["qr_device_key_button"]
        try skipIfFalse(deviceKeyButton.waitForExistence(timeout: 8), "Device key action not found")
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

        if app.otherElements["settings_navigation_view"].waitForExistence(timeout: 10)
            || app.otherElements["screen_settings_ipad"].waitForExistence(timeout: 10)
            || selectTab(index: 3, expectedIdentifier: "screen_settings_ipad") {
            captureScenarioScreenshot(index: 10, slug: "settings-navigation")
            return
        }

        throw XCTSkip("Settings navigation container is not reachable")
    }
}
