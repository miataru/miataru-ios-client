/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * miataruApp.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import Combine
import UIKit
import UserNotifications

private enum UITestLaunchArgument {
    static let uiTesting = "-ui-testing"
    static let resetUserDefaults = "-ui-reset-userdefaults"
    static let onboardingCompleted = "-ui-onboarding-completed"
    static let showOnboarding = "-ui-show-onboarding"
    static let disableLocationTracking = "-ui-disable-location-tracking"
    static let initialTab = "-ui-initial-tab"
    static let screenshotMode = "-ui-screenshot-mode"
    static let screenshotScenario = "-ui-screenshot-scenario"
}

extension UserDefaults {
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: "hasCompletedOnboarding") }
        set { set(newValue, forKey: "hasCompletedOnboarding") }
    }

    var hasShownPostUpdateOnboarding: Bool {
        get { bool(forKey: "hasShownPostUpdateOnboarding") }
        set { set(newValue, forKey: "hasShownPostUpdateOnboarding") }
    }

    var hadLocationTrackingEnabled: Bool {
        bool(forKey: "track_and_report_location")
    }
}

class AppState: ObservableObject {
    @Published var showOnboarding: Bool
    @Published var onboardingMode: OnboardingMode

    init() {
        let defaults = UserDefaults.standard
        if !defaults.hasCompletedOnboarding {
            onboardingMode = .full
            showOnboarding = true
            return
        }

        if !defaults.hasShownPostUpdateOnboarding, defaults.hadLocationTrackingEnabled {
            onboardingMode = .postUpdate
            showOnboarding = true
            return
        }

        onboardingMode = .full
        showOnboarding = false
    }

    func presentFullOnboarding(skipPostUpdate: Bool) {
        if skipPostUpdate {
            UserDefaults.standard.hasShownPostUpdateOnboarding = true
        }
        onboardingMode = .full
        showOnboarding = true
    }
}

@MainActor
fileprivate final class LaunchGuard {
    static var isFirstActivation: Bool = true
}

fileprivate final class RotationLockController {
    static let shared = RotationLockController()

    private var isRotationLocked = false
    private var lockedOrientationMask: UIInterfaceOrientationMask = .portrait

    private init() {}

    func supportedInterfaceOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard isRotationLocked else { return .all }
        return lockedOrientationMask
    }

    func setRotationLockEnabled(_ enabled: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.setRotationLockEnabled(enabled)
            }
            return
        }

        isRotationLocked = enabled
        if enabled {
            lockedOrientationMask = currentInterfaceOrientationMask()
        }

        let targetMask = isRotationLocked ? lockedOrientationMask : .all
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            if #available(iOS 16.0, *) {
                let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMask)
                scene.requestGeometryUpdate(preferences) { error in
                    debugLog("Failed to update orientation preferences: \(error.localizedDescription)")
                }
            }
        }

    }

    private func currentInterfaceOrientationMask() -> UIInterfaceOrientationMask {
        if let orientation = currentInterfaceOrientation() {
            return mask(for: orientation)
        }
        return .portrait
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return activeScene.interfaceOrientation
        }
        return scenes.first?.interfaceOrientation
    }

    private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        RotationLockController.shared.supportedInterfaceOrientations(for: window)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let type = userInfo[UnknownVisitorAlertService.notificationTypeUserInfoKey] as? String,
           type == UnknownVisitorAlertService.unknownVisitorNotificationType {
            completionHandler([.banner, .list, .sound])
            return
        }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let type = userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String,
           Self.opensAdvancedSettingsNotificationTypes.contains(type) {
            Task { @MainActor in
                AppNavigationCoordinator.shared.openAdvancedSettings()
            }
            completionHandler()
            return
        }

        completionHandler()
    }

    private static let opensAdvancedSettingsNotificationTypes: Set<String> = [
        FrequentBackgroundTrackingReminderService.notificationType,
        FrequentBackgroundTrackingReminderService.expirationNotificationType,
        FrequentBackgroundTrackingReminderService.batteryAutoDisableNotificationType
    ]
}

@main
struct miataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @State private var autolockCancellable: AnyCancellable? = nil
    @State private var rotationLockCancellable: AnyCancellable? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        Self.applyUITestLaunchConfiguration()
        let shouldSkipExistingInstallMigration = ProcessInfo.processInfo.arguments.contains(UITestLaunchArgument.resetUserDefaults)
        SettingsMigration.applyExistingInstallDefaultsIfNeeded(
            defaults: UserDefaults.standard,
            skipForFreshUITestReset: shouldSkipExistingInstallMigration
        )
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        // Beim ersten Start oder für einen Reset:
        //SettingsManager.shared.loadSettingsFromPlist(plistName: "Root")
        _appState = StateObject(wrappedValue: AppState())

        let deviceID = thisDeviceIDManager.shared.deviceID
        debugLog("this devices ID: \(deviceID)")
        
        // LocationManager initialisieren und Berechtigungen nur anfordern, wenn gewünscht
        let locationManager = LocationManager.shared
        if SettingsManager.shared.trackAndReportLocation {
            locationManager.requestLocationPermission()
        }
        // Preserve newer widget-fetched locations before rewriting shared widget data.
        WidgetDataSyncCoordinator.importNewerWidgetLocationsIntoAppCache()
        // Ensure widgets have initial data even before the first update cycle.
        WidgetDataSyncCoordinator.syncAllDevices()
        Task { @MainActor in
            PersistentDataCleanup.run()
        }
        // Do NOT call startTracking() here!
        // Tracking is now controlled by the observer in LocationManager.observeSettings().
        // The observer listens to changes in SettingsManager.shared.trackAndReportLocation.
        // If the setting is enabled, tracking will start automatically.
        // If the setting is disabled, tracking will be stopped automatically.
        // This ensures the app always respects the user's preference, even on app launch.
        // locationManager.startTracking() // Removed to ensure correct behavior
        
        // Debuging: Remove before flight !!!!! ##########################
        //UserDefaults.standard.hasCompletedOnboarding = false
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            MiataruRootView()
                .environmentObject(appState)
                .environmentObject(RouteInfoState.shared)
                .environmentObject(SettingsManager.shared)
                .animationsGate()
                .fullScreenCover(isPresented: $appState.showOnboarding) {
                    OnboardingContainerView(isPresented: $appState.showOnboarding, mode: appState.onboardingMode)
                        .background(Color(.systemBackground))
                        .ignoresSafeArea()
                }
                .onAppear {
#if os(iOS)
                    // Set initial value
                    UIApplication.shared.isIdleTimerDisabled = SettingsManager.shared.disableDeviceAutolock
                    // Subscribe to changes
                    autolockCancellable = SettingsManager.shared.$disableDeviceAutolock.sink { value in
                        UIApplication.shared.isIdleTimerDisabled = value
                    }
                    // Apply and observe app-wide rotation lock setting.
                    rotationLockCancellable = SettingsManager.shared.$preventScreenRotation
                        .receive(on: RunLoop.main)
                        .removeDuplicates()
                        .sink { isEnabled in
                            RotationLockController.shared.setRotationLockEnabled(isEnabled)
                        }
#endif
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .sheet(isPresented: $showAddDeviceSheet, onDismiss: { pendingDeviceID = nil }) {
                    if let deviceID = pendingDeviceID {
                        iPhone_AddDeviceView(store: KnownDeviceStore.shared, isPresented: $showAddDeviceSheet, prefillDeviceID: deviceID)
                    }
                }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                WidgetDataSyncCoordinator.importNewerWidgetLocationsIntoAppCache()
                LocationManager.shared.appDidEnterForeground()
            case .background:
                LocationManager.shared.appDidEnterBackground()
            default:
                break
            }
        }
        WindowGroup(for: String.self) { deviceID in
            DeviceWindowEntrypoint(deviceID: deviceID)
                .environmentObject(RouteInfoState.shared)
                .environmentObject(SettingsManager.shared)
                .animationsGate()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "miataru" else { return }
        let deviceID = url.host ?? ""
        guard !deviceID.isEmpty else { return }

        Task { @MainActor in
            // When resuming from background, SwiftUI may restore navigation state after the URL
            // event is delivered. Deferring slightly ensures the deep link wins over restoration.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)

            // If the device already exists, navigate to it; otherwise fall back to add flow.
            if KnownDeviceStore.shared.devices.contains(where: { $0.DeviceID == deviceID }) {
                showAddDeviceSheet = false
                pendingDeviceID = nil
                SettingsManager.shared.lastOpenedDeviceID = deviceID
            } else {
                pendingDeviceID = deviceID
                showAddDeviceSheet = true
            }
        }
    }

    private static func applyUITestLaunchConfiguration() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(UITestLaunchArgument.uiTesting) else { return }

        let defaults = UserDefaults.standard
        if args.contains(UITestLaunchArgument.resetUserDefaults),
           let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }

        if args.contains(UITestLaunchArgument.showOnboarding) {
            defaults.hasCompletedOnboarding = false
            defaults.hasShownPostUpdateOnboarding = false
        }

        if args.contains(UITestLaunchArgument.onboardingCompleted) {
            defaults.hasCompletedOnboarding = true
            defaults.hasShownPostUpdateOnboarding = true
        }

        if args.contains(UITestLaunchArgument.disableLocationTracking) {
            defaults.set(false, forKey: "track_and_report_location")
        }

        let hasExplicitInitialTab: Bool
        if let initialTabIndex = args.firstIndex(of: UITestLaunchArgument.initialTab),
           args.indices.contains(initialTabIndex + 1),
           let tabValue = Int(args[initialTabIndex + 1]) {
            defaults.set(tabValue, forKey: "ui_test_initial_tab")
            hasExplicitInitialTab = true
        } else {
            defaults.removeObject(forKey: "ui_test_initial_tab")
            hasExplicitInitialTab = false
        }

        let isScreenshotMode = args.contains(UITestLaunchArgument.screenshotMode)
        defaults.set(isScreenshotMode, forKey: "ui_test_is_screenshot_mode")

        var screenshotScenarioID: String?
        if let scenarioIndex = args.firstIndex(of: UITestLaunchArgument.screenshotScenario),
           args.indices.contains(scenarioIndex + 1) {
            screenshotScenarioID = args[scenarioIndex + 1]
            defaults.set(screenshotScenarioID, forKey: "ui_test_screenshot_scenario")
        } else {
            defaults.removeObject(forKey: "ui_test_screenshot_scenario")
        }

        if isScreenshotMode {
            applyUIScreenshotDeterministicState(
                defaults: defaults,
                scenarioID: screenshotScenarioID,
                hasExplicitInitialTab: hasExplicitInitialTab
            )
        }
    }

    private static func applyUIScreenshotDeterministicState(defaults: UserDefaults,
                                                            scenarioID: String?,
                                                            hasExplicitInitialTab: Bool) {
        defaults.set(false, forKey: "track_and_report_location")
        defaults.set(true, forKey: "hasShownPostUpdateOnboarding")
        defaults.removeObject(forKey: "lastOpenedDeviceID")

        guard !hasExplicitInitialTab, let scenarioID else { return }

        switch scenarioID {
        case "root-devices", "devices-add-sheet":
            defaults.set(0, forKey: "ui_test_initial_tab")
        case "root-qr", "qr-device-key":
            defaults.set(1, forKey: "ui_test_initial_tab")
        case "root-settings", "settings-show-onboarding", "settings-navigation":
            defaults.set(2, forKey: "ui_test_initial_tab")
        case "groups-tab":
            defaults.set(1, forKey: "ui_test_initial_tab")
        default:
            break
        }
    }
}

private struct DeviceWindowEntrypoint: View {
    @Binding var deviceID: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    init(deviceID: Binding<String?>) {
        self._deviceID = deviceID
    }

    var body: some View {
        Group {
            if let id = deviceID {
                iPad_DeviceMapView(deviceID: id, shouldUpdateLastOpenedDeviceID: false)
            } else {
                Text(NSLocalizedString("no_device_selected", comment: "No device selected for this window."))
            }
        }
        .task {
            if LaunchGuard.isFirstActivation {
                LaunchGuard.isFirstActivation = false
                openWindow(id: "main")
                if let id = deviceID {
                    dismissWindow(value: id)
                }
            }
        }
    }
}
