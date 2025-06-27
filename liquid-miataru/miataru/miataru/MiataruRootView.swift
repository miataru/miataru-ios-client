//
//  ContentView.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//
import SwiftUI

struct MiataruRootView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        #if os(macOS)
        // Mac-spezifische View
        //MacRootView()
        iPhone_RootView() // for now
        #else
        if horizontalSizeClass == .compact {
            // iPhone-spezifische View
            iPhone_RootView()
        } else {
            // iPad-spezifische View
            //iPad_RootView()
            iPhone_RootView() // for now
        }
        #endif
    }
}

#Preview {
    MiataruRootView()
}
