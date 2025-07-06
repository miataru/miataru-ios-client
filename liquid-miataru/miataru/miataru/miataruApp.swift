//
//  miataruApp.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

extension UserDefaults {
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: "hasCompletedOnboarding") }
        set { set(newValue, forKey: "hasCompletedOnboarding") }
    }
}

class AppState: ObservableObject {
    @Published var showOnboarding: Bool = !UserDefaults.standard.hasCompletedOnboarding
}

@main
struct miataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    
    init() {
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        // Beim ersten Start oder für einen Reset:
        //SettingsManager.shared.loadSettingsFromPlist(plistName: "Root")
        let deviceID = thisDeviceIDManager.shared.deviceID
        print("this devices ID: \(deviceID)")
        
        // LocationManager initialisieren und Berechtigungen anfordern
        let locationManager = LocationManager.shared
        locationManager.requestLocationPermission()
        // Stelle sicher, dass das Tracking direkt beim App-Start aktiviert wird
        locationManager.startTracking()
        
        // Debuging: Remove before flight !!!!! ##########################
        //UserDefaults.standard.hasCompletedOnboarding = false
     
    }
    
    var body: some Scene {
        WindowGroup {
            MiataruRootView()
                .environmentObject(appState)
                .fullScreenCover(isPresented: $appState.showOnboarding) {
                    OnboardingContainerView(isPresented: $appState.showOnboarding)
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
    }
}
