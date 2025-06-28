//
//  miataruApp.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

@main
struct miataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        // Beim ersten Start oder für einen Reset:
        //SettingsManager.shared.loadSettingsFromPlist(plistName: "Root")
        let deviceID = thisDeviceIDManager.shared.deviceID
        print("this devices ID: \(deviceID)")
        
        // LocationManager initialisieren und Berechtigungen anfordern
        let locationManager = LocationManager.shared
        locationManager.requestLocationPermission()
        
        // BackgroundLocationManager initialisieren
        let backgroundManager = BackgroundLocationManager.shared
        print("Background Location Manager initialisiert")
    }
    
    var body: some Scene {
        WindowGroup {
            MiataruRootView()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                print("App ist aktiv")
                BackgroundLocationManager.shared.handleAppWillEnterForeground()
            case .inactive:
                print("App ist inaktiv")
            case .background:
                print("App ist im Hintergrund")
                BackgroundLocationManager.shared.handleAppDidEnterBackground()
            @unknown default:
                break
            }
        }
    }
}
