import SwiftUI

struct iPhone_AddGroupView: View {
    @ObservedObject var groupStore: DeviceGroupStore
    @Binding var isPresented: Bool
    @State private var groupName: String = ""
    @State private var groupColor: Color = .blue

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("group_name")) {
                    TextField("group_name_placeholder", text: $groupName)
                }
                Section(header: Text("group_color")) {
                    ColorPicker("group_color_picker", selection: $groupColor)
                }
            }
            .navigationTitle("new_group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
                        let uiColor = UIColor(groupColor)
                        let newGroup = DeviceGroup(name: groupName, color: uiColor)
                        groupStore.add(group: newGroup)
                        isPresented = false
                    }
                    .disabled(groupName.isEmpty)
                }
            }
        }
    }
}

#Preview {
    let groupStore = DeviceGroupStore()
    return iPhone_AddGroupView(groupStore: groupStore, isPresented: .constant(true))
} 