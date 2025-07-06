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
        // Stelle sicher, dass das Tracking direkt beim App-Start aktiviert wird
        locationManager.startTracking()
        
        // BackgroundLocationManager initialisieren
        //_ = BackgroundLocationManager.shared
        //print("Background Location Manager initialisiert")
    }
    
    var body: some Scene {
        WindowGroup {
            MiataruRootView()
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
