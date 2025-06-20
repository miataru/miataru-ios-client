import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Verlaufseintrag 1")
                Text("Verlaufseintrag 2")
            }
            .navigationTitle("Verlauf")
        }
    }
}

#Preview {
    HistoryView()
} 