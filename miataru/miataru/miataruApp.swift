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
    private var didRestoreTrackingForLocationLaunch = false

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        restoreTrackingForLocationLaunchIfNeeded(launchOptions)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        restoreTrackingForLocationLaunchIfNeeded(launchOptions)
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
        if let type = userInfo[UnknownVisitorAlertService.notificationTypeUserInfoKey] as? String,
           type == UnknownVisitorAlertService.unknownVisitorNotificationType,
           let deviceID = userInfo[UnknownVisitorAlertService.notificationDeviceIDUserInfoKey] as? String {
            let visitDate = Self.unknownVisitorVisitDate(from: userInfo)
            Task { @MainActor in
                AppNavigationCoordinator.shared.openUnknownVisitorNotificationDevice(deviceID, visitDate: visitDate)
            }
            completionHandler()
            return
        }

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
        FrequentBackgroundTrackingReminderService.batteryAutoDisableNotificationType,
        FrequentBackgroundTrackingReminderService.smartFrequentActivatedNotificationType,
        FrequentBackgroundTrackingReminderService.smartFrequentDeactivatedNotificationType
    ]

    static func didLaunchForLocation(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        launchOptions?[.location] != nil
    }

    static func shouldRestoreLocationLaunch(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?, didRestore: Bool) -> Bool {
        didLaunchForLocation(launchOptions) && !didRestore
    }

    private func restoreTrackingForLocationLaunchIfNeeded(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard Self.shouldRestoreLocationLaunch(launchOptions, didRestore: didRestoreTrackingForLocationLaunch) else {
            return
        }

        didRestoreTrackingForLocationLaunch = true
        LocationManager.shared.restoreTrackingAfterLaunch(
            reason: "location launch",
            applicationStateContext: .forceBackground
        )
    }

    private static func unknownVisitorVisitDate(from userInfo: [AnyHashable: Any]) -> Date? {
        let rawValue = userInfo[UnknownVisitorAlertService.notificationVisitTimestampUserInfoKey]
        let timestampMs: Int64?

        if let value = rawValue as? Int64 {
            timestampMs = value
        } else if let value = rawValue as? Int {
            timestampMs = Int64(value)
        } else if let value = rawValue as? NSNumber {
            timestampMs = value.int64Value
        } else if let value = rawValue as? String {
            timestampMs = Int64(value)
        } else {
            timestampMs = nil
        }

        guard let timestampMs else { return nil }
        return Date(timeIntervalSince1970: Double(timestampMs) / 1_000.0)
    }
}

@main
struct miataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var appNavigation = AppNavigationCoordinator.shared
    @State private var autolockCancellable: AnyCancellable? = nil
    @State private var rotationLockCancellable: AnyCancellable? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    @State private var pendingAddDeviceSource: AddDeviceRequestSource = .general
    @State private var activeUnknownDeviceAction: UnknownDeviceActionRequest? = nil
    @State private var unknownDeviceActionDetent: PresentationDetent = .large
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
        
        // LocationManager initialisieren und Tracking nach App-/Location-Launch rekonstruieren.
        let locationManager = LocationManager.shared
        if SettingsManager.shared.trackAndReportLocation {
            locationManager.restoreTrackingAfterLaunch(reason: "app launch")
        }
        locationManager.rearmSignificantChangeMonitorAfterFreshLaunchIfNeeded(
            buildIdentifier: Self.currentBuildIdentifier,
            reason: "fresh app/update launch"
        )
        // Preserve newer widget-fetched locations before rewriting shared widget data.
        WidgetDataSyncCoordinator.importNewerWidgetLocationsIntoAppCache()
        // Ensure widgets have initial data even before the first update cycle.
        WidgetDataSyncCoordinator.syncAllDevices()
        Task { @MainActor in
            PersistentDataCleanup.run()
        }
        // Runtime toggle changes remain controlled by LocationManager.observeSettings().
        
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
                    presentAddDeviceRequest(appNavigation.addDeviceRequest)
                    presentUnknownDeviceActionRequest(appNavigation.unknownDeviceActionRequest)
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onChange(of: appNavigation.addDeviceRequest) { _, request in
                    presentAddDeviceRequest(request)
                }
                .onChange(of: appNavigation.unknownDeviceActionRequest) { _, request in
                    presentUnknownDeviceActionRequest(request)
                }
                .sheet(isPresented: $showAddDeviceSheet, onDismiss: {
                    pendingDeviceID = nil
                    pendingAddDeviceSource = .general
                }) {
                    if let deviceID = pendingDeviceID {
                        iPhone_AddDeviceView(
                            store: KnownDeviceStore.shared,
                            isPresented: $showAddDeviceSheet,
                            prefillDeviceID: deviceID,
                            allowsDeviceIDEditing: pendingAddDeviceSource != .unknownVisitor
                        )
                    }
                }
                .sheet(item: $activeUnknownDeviceAction) { request in
                    UnknownDeviceActionSheet(
                        deviceID: request.deviceID,
                        visitDate: request.visitDate,
                        addActionTitle: unknownDeviceAddActionTitle,
                        message: unknownDeviceActionMessage,
                        onAdd: {
                            activeUnknownDeviceAction = nil
                            Task { @MainActor in
                                await Task.yield()
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                openUnknownDeviceAddOrKnownDevice(request.deviceID)
                            }
                        },
                        onIgnore: {
                            IgnoredVisitorDeviceStore.shared.addIgnored(deviceID: request.deviceID)
                            Haptic.notifySuccess()
                            activeUnknownDeviceAction = nil
                        },
                        onCancel: {
                            activeUnknownDeviceAction = nil
                        }
                    )
                    .presentationDetents([.medium, .large], selection: $unknownDeviceActionDetent)
                    .presentationDragIndicator(.visible)
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
        guard let destination = DeviceLinkResolver.destination(from: url) else { return }

        Task { @MainActor in
            // When resuming from background, SwiftUI may restore navigation state after the URL
            // event is delivered. Deferring slightly ensures the deep link wins over restoration.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)

            let deviceID: String
            switch destination {
            case .device(let rawDeviceID), .navigation(let rawDeviceID, _):
                deviceID = rawDeviceID
            }

            if DeviceLinkResolver.canonicalKnownDeviceID(for: deviceID) != nil {
                showAddDeviceSheet = false
                pendingDeviceID = nil
                pendingAddDeviceSource = .general
            }
            appNavigation.openDeviceLink(destination)
        }
    }

    @MainActor
    private func presentAddDeviceRequest(_ request: AddDeviceRequest?) {
        guard let request else { return }
        pendingDeviceID = request.deviceID
        pendingAddDeviceSource = request.source
        activeUnknownDeviceAction = nil
        showAddDeviceSheet = true
        appNavigation.consumeAddDeviceRequest(request)
    }

    @MainActor
    private func presentUnknownDeviceActionRequest(_ request: UnknownDeviceActionRequest?) {
        guard let request else { return }
        unknownDeviceActionDetent = .large
        activeUnknownDeviceAction = request
        appNavigation.consumeUnknownDeviceActionRequest(request)
    }

    private var unknownDeviceAddActionTitle: String {
        if SettingsManager.shared.allowedDeviceListEnabled {
            return NSLocalizedString("unknown_visitor_add_and_allow", comment: "Action to add an unknown visitor device and allow access")
        }
        return NSLocalizedString("add", comment: "Add")
    }

    private var unknownDeviceActionMessage: String {
        if SettingsManager.shared.allowedDeviceListEnabled {
            return NSLocalizedString("unknown_device_actions_message_acl_enabled", comment: "Dialog message for an unknown device when the allowed device list is enabled.")
        }
        return NSLocalizedString("unknown_device_actions_message_acl_disabled", comment: "Dialog message for an unknown device when the allowed device list is disabled.")
    }

    @MainActor
    private func openUnknownDeviceAddOrKnownDevice(_ rawDeviceID: String) {
        if let knownDeviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
            appNavigation.openKnownDevice(knownDeviceID)
        } else {
            appNavigation.openAddDevice(rawDeviceID, source: .unknownVisitor)
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

    private static var currentBuildIdentifier: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version)-\(build)"
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

private struct UnknownDeviceActionSheet: View {
    let deviceID: String
    let visitDate: Date?
    let addActionTitle: String
    let message: String
    let onAdd: () -> Void
    let onIgnore: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    @ObservedObject private var locationCache = DeviceLocationCacheStore.shared

    private var sloganText: String? {
        guard let slogan = sloganCache.slogan(for: deviceID), !slogan.isEmpty else { return nil }
        return slogan
    }

    private var locationText: String? {
        if let cached = locationCache.getLocation(for: deviceID) {
            if let locality = cached.locality, let country = cached.country {
                return "\(locality), \(country)"
            }
            if let locality = cached.locality {
                return locality
            }
            if let country = cached.country {
                return country
            }
        }

        if let placemark = locationCache.getPlacemark(for: deviceID) {
            if let locality = placemark.locality, let country = placemark.country {
                return "\(locality), \(country)"
            }
            if let locality = placemark.locality {
                return locality
            }
            if let country = placemark.country {
                return country
            }
        }

        return nil
    }

    private var formattedVisitDate: String? {
        guard let visitDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: visitDate, relativeTo: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label {
                            Text("unknown_device_actions_title")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .labelStyle(.titleAndIcon)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        UnknownDeviceInfoRow(systemImage: "number", value: deviceID, monospaced: true)

                        if let sloganText {
                            UnknownDeviceInfoRow(systemImage: "text.quote", value: sloganText)
                        }

                        if let locationText {
                            UnknownDeviceInfoRow(systemImage: "mappin.and.ellipse", value: locationText)
                        }

                        if let formattedVisitDate {
                            UnknownDeviceInfoRow(systemImage: "clock", value: formattedVisitDate)
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: onAdd) {
                            Label(addActionTitle, systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(role: .destructive, action: onIgnore) {
                            Label(
                                NSLocalizedString("allowed_device_list_ignore_button", comment: "Button to ignore an unknown visitor device"),
                                systemImage: "eye.slash"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                locationCache.enqueueGeocodingIfNeeded(for: deviceID)
            }
            .navigationTitle("unknown_device_actions_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel", role: .cancel, action: onCancel)
                }
            }
        }
    }
}

private struct UnknownDeviceInfoRow: View {
    let systemImage: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(value)
                .font(monospaced ? Font.footnote.monospaced() : Font.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
