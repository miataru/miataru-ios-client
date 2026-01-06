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
}

class AppState: ObservableObject {
    @Published var showOnboarding: Bool = !UserDefaults.standard.hasCompletedOnboarding
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
    @StateObject private var appState = AppState()
    @State private var autolockCancellable: AnyCancellable? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        // Beim ersten Start oder für einen Reset:
        //SettingsManager.shared.loadSettingsFromPlist(plistName: "Root")
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
                .fullScreenCover(isPresented: $appState.showOnboarding) {
                    OnboardingContainerView(isPresented: $appState.showOnboarding)
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
                    if url.scheme == "miataru" {
                        let deviceID = url.host?.uppercased() ?? ""
                        if !deviceID.isEmpty {
                            // If the device already exists, navigate to it; otherwise fall back to add flow.
                            if KnownDeviceStore.shared.devices.contains(where: { $0.DeviceID == deviceID }) {
                                SettingsManager.shared.lastOpenedDeviceID = deviceID
                            } else {
                                pendingDeviceID = deviceID
                                showAddDeviceSheet = true
                            }
                        }
                    }
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
                iPad_DeviceMapView(deviceID: id)
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
