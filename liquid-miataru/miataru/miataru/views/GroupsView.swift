import SwiftUI

struct GroupsView: View {
    var body: some View {
        NavigationView {
            List {
                Text("Gruppe 1")
                Text("Gruppe 2")
            }
            .navigationTitle("Gruppen")
        }
    }
}

#Preview {
    GroupsView()
} 