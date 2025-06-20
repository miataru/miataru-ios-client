import SwiftUI

struct MapView: View {
    var body: some View {
        VStack {
            Text("Kartenansicht")
                .font(.title)
                .padding()
            Text("Kartentyp: \(SettingsManager.shared.mapType)")
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(height: 300)
                .cornerRadius(12)
                .overlay(Text("Hier könnte eine Karte sein").foregroundColor(.gray))
        }
        .navigationTitle("Karte")
    }
}

#Preview {
    MapView()
} 