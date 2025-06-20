import SwiftUI

struct DevicesView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Gerät 1")
                Text("Gerät 2")
            }
            .navigationTitle("Geräte")
        }
    }
}

#Preview {
    DevicesView()
} 