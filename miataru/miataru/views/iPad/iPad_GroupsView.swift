import SwiftUI

struct iPad_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var selection: String? = nil // groupID
    @State private var showingAddGroup = false
    @State private var editingGroup: DeviceGroup? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text("groups")) {
                    ForEach(groupStore.groups) { group in
                        iPhone_GroupRowView(group: group)
                            .tag(group.id)
                            .contextMenu {
                                Button {
                                    editingGroup = group
                                } label: {
                                    Label("edit_group", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    groupStore.remove(group: group)
                                } label: {
                                    Label("delete_group", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indices in
                        groupStore.remove(atOffsets: indices)
                    }
                    .onMove { indices, newOffset in
                        groupStore.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }
            .navigationTitle("groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode == .active ? "grouplist_edit_done" : "grouplist_editbutton") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGroup = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .environment(\.editMode, $editMode)
        } detail: {
            if let selectedID = selection, let group = groupStore.groups.first(where: { $0.id == selectedID }) {
                iPhone_GroupMapView(group: group)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { editingGroup = group }) {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                    .sheet(item: $editingGroup) { group in
                        iPhone_GroupDetailView(group: group)
                    }
            } else {
                Text("Select a group to view details")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
        }
    }
}

#Preview {
    iPad_GroupsView().environmentObject(DeviceGroupStore.shared)
} 