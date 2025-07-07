import SwiftUI

struct iPhone_EditGroupNameView: View {
    @ObservedObject var group: DeviceGroup
    @Binding var isPresented: Bool
    @State private var tempGroupName: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("group_name")) {
                    TextField("group_name_placeholder", text: $tempGroupName)
                }
            }
            .navigationTitle("edit_group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        group.groupName = tempGroupName
                        isPresented = false
                    }
                    .disabled(tempGroupName.isEmpty)
                }
            }
        }
        .onAppear {
            tempGroupName = group.groupName
        }
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    return iPhone_EditGroupNameView(group: group, isPresented: .constant(true))
} 