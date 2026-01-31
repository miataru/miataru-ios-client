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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }
}

@main
struct miataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @State private var autolockCancellable: AnyCancellable? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
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
        // Ensure widgets have initial data even before the first update cycle.
        WidgetDataSyncCoordinator.syncAllDevices()
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
