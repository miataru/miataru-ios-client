//
//  miataruApp.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

@main
struct miataruApp: App {
    init() {
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        // Beim ersten Start oder für einen Reset:
        //SettingsManager.shared.loadSettingsFromPlist(plistName: "Root")
    }
    var body: some Scene {
        WindowGroup {
            MiataruRootView()
        }
    }
}
