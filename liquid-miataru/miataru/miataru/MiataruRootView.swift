//
//  ContentView.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

//struct ContentView: View {
//    var body: some View {
//        VStack {
//            Image(systemName: "globe")
//                .imageScale(.large)
//                .foregroundStyle(.tint)
//            Text("Hello, world!")
//        }
//        .padding()
//    }
//}
//
//#Preview {
//    ContentView()
//}

struct MiataruRootView: View {
    var body: some View {
        TabView {
            DevicesView()
                .tabItem {
                    Label("Geräte", systemImage: "iphone.gen3.badge.location")
                }
            GroupsView()
                .tabItem {
                    Label("Gruppen", systemImage: "person.3")
                }
            MyDeviceQRCodeView()
                .tabItem {
                    Label("QR", systemImage: "qrcode")
                }
            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MiataruRootView()
}
