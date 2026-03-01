import XCTest

class ScreenshotBaseUITestCase: XCTestCase {
    let supportedScreenshotLanguages = ["en", "de", "ja", "fr", "es", "zh-Hans", "nl", "da", "it", "fi"]

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
        let languageCode = screenshotLanguageCode()
        let regionCode = screenshotRegionCode()
        args += [
            "-AppleLanguages", "(\(appleLanguageIdentifier(for: languageCode)))",
            "-AppleLocale", appleLocaleIdentifier(languageCode: languageCode, regionCode: regionCode)
        ]

        if onboardingCompleted {
            args.append("-ui-onboarding-completed")
        } else {
            args.append("-ui-show-onboarding")
        }

        if let initialTab {
            args += ["-ui-initial-tab", String(initialTab)]
        }

        app.launchArguments = args
        app.launchEnvironment["SCREENSHOT_LANG"] = languageCode
        app.launchEnvironment["SCREENSHOT_REGION"] = regionCode
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
        if let envLang, !envLang.isEmpty, let normalized = normalizeLanguageCode(envLang) {
            return normalized
        }

        if let appleLanguage = languageFromAppleLanguageSettings() {
            return appleLanguage
        }

        let preferred = Locale.preferredLanguages.first ?? "en"
        return normalizeLanguageCode(preferred) ?? "en"
    }

    func screenshotDeviceName() -> String {
        let envDevice = ProcessInfo.processInfo.environment["SCREENSHOT_DEVICE_NAME"]
        if let envDevice, !envDevice.isEmpty {
            return envDevice
        }

        return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown-device"
    }

    func screenshotRegionCode() -> String {
        let envRegion = ProcessInfo.processInfo.environment["SCREENSHOT_REGION"]
        if let envRegion, !envRegion.isEmpty {
            return envRegion
        }
        if let regionFromAppleLocale = regionFromAppleLocaleSettings() {
            return regionFromAppleLocale
        }
        return Locale.current.region?.identifier ?? "US"
    }

    func appleLanguageIdentifier(for languageCode: String) -> String {
        if languageCode == "zh-Hans" {
            return "zh-Hans"
        }
        return languageCode.components(separatedBy: "-").first ?? languageCode
    }

    func appleLocaleIdentifier(languageCode: String, regionCode: String) -> String {
        if languageCode == "zh-Hans" {
            return "zh_Hans_\(regionCode)"
        }
        let normalizedLanguage = languageCode.replacingOccurrences(of: "-", with: "_")
        return "\(normalizedLanguage)_\(regionCode)"
    }

    func languageFromAppleLanguageSettings() -> String? {
        let processInfo = ProcessInfo.processInfo

        if let envAppleLanguages = processInfo.environment["AppleLanguages"],
           let rawLanguage = firstLanguageToken(fromAppleLanguagesValue: envAppleLanguages),
           let normalized = normalizeLanguageCode(rawLanguage) {
            return normalized
        }

        if let argIndex = processInfo.arguments.firstIndex(of: "-AppleLanguages"),
           processInfo.arguments.indices.contains(argIndex + 1),
           let rawLanguage = firstLanguageToken(fromAppleLanguagesValue: processInfo.arguments[argIndex + 1]),
           let normalized = normalizeLanguageCode(rawLanguage) {
            return normalized
        }

        return nil
    }

    func regionFromAppleLocaleSettings() -> String? {
        let processInfo = ProcessInfo.processInfo

        if let envAppleLocale = processInfo.environment["AppleLocale"],
           let region = parseRegionCode(fromAppleLocale: envAppleLocale) {
            return region
        }

        if let argIndex = processInfo.arguments.firstIndex(of: "-AppleLocale"),
           processInfo.arguments.indices.contains(argIndex + 1),
           let region = parseRegionCode(fromAppleLocale: processInfo.arguments[argIndex + 1]) {
            return region
        }

        return nil
    }

    func firstLanguageToken(fromAppleLanguagesValue value: String) -> String? {
        var raw = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\"", with: "")

        if let separatorIndex = raw.firstIndex(where: { $0 == "," || $0 == ";" }) {
            raw = String(raw[..<separatorIndex])
        }

        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    func normalizeLanguageCode(_ rawLanguageCode: String) -> String? {
        let raw = rawLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let lowered = raw.lowercased()
        if lowered.hasPrefix("zh-hans") || lowered.hasPrefix("zh_hans") || lowered == "zh" {
            return "zh-Hans"
        }

        let primaryLanguage = lowered
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-")
            .first ?? lowered

        let normalizedPrimary = primaryLanguage.lowercased()
        for language in supportedScreenshotLanguages where language.lowercased() == normalizedPrimary {
            return language
        }
        return nil
    }

    func parseRegionCode(fromAppleLocale value: String) -> String? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\"", with: "")

        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: "-_"))
        if let regionPart = parts.last, regionPart.count == 2 {
            return regionPart.uppercased()
        }
        return nil
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
