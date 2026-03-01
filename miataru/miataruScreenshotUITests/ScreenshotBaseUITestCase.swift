import XCTest

class ScreenshotBaseUITestCase: XCTestCase {
    let baseLaunchArguments = [
        "-ui-testing",
        "-ui-reset-userdefaults",
        "-ui-disable-location-tracking",
        "-ui-screenshot-mode"
    ]

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    @MainActor
    func launchApp(onboardingCompleted: Bool, initialTab: Int? = nil, scenarioID: String) -> XCUIApplication {
        var args = baseLaunchArguments + ["-ui-screenshot-scenario", scenarioID]

        if onboardingCompleted {
            args.append("-ui-onboarding-completed")
        } else {
            args.append("-ui-show-onboarding")
        }

        if let initialTab {
            args += ["-ui-initial-tab", String(initialTab)]
        }

        app.launchArguments = args
        app.launchEnvironment["SCREENSHOT_LANG"] = screenshotLanguageCode()
        app.launchEnvironment["SCREENSHOT_DEVICE_NAME"] = screenshotDeviceName()
        app.launch()
        return app
    }

    @MainActor
    func captureScenarioScreenshot(index: Int, slug: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = screenshotFileName(index: index, slug: slug)
        add(attachment)
    }

    func screenshotLanguageCode() -> String {
        let envLang = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"]
        if let envLang, !envLang.isEmpty {
            return envLang
        }

        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.components(separatedBy: "-").first ?? "en"
    }

    func screenshotDeviceName() -> String {
        let envDevice = ProcessInfo.processInfo.environment["SCREENSHOT_DEVICE_NAME"]
        if let envDevice, !envDevice.isEmpty {
            return envDevice
        }

        return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown-device"
    }

    func screenshotFileName(index: Int, slug: String) -> String {
        let language = sanitizeToken(screenshotLanguageCode())
        let device = sanitizeToken(screenshotDeviceName())
        let padded = String(format: "%02d", index)
        return "\(padded)_\(sanitizeToken(slug))__\(language)__\(device).png"
    }

    func sanitizeToken(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            if char == "-" || char == "_" {
                return char
            }
            return "-"
        }

        let squashed = String(mapped).replacingOccurrences(of: "--", with: "-")
        return squashed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func waitForElementByScrollingUp(in app: XCUIApplication, element: XCUIElement, maxSwipes: Int) -> Bool {
        if element.waitForExistence(timeout: 1.0) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: 0.8) {
                return true
            }
        }

        return false
    }

    @MainActor
    func selectTab(index: Int, expectedIdentifier: String) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return false }

        let targetTab = tabBar.buttons.element(boundBy: index)
        guard targetTab.waitForExistence(timeout: 5) else { return false }

        if targetTab.isHittable {
            targetTab.tap()
        }

        return app.otherElements[expectedIdentifier].waitForExistence(timeout: 8)
    }

    @MainActor
    func skipIfFalse(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw XCTSkip(message)
        }
    }
}
