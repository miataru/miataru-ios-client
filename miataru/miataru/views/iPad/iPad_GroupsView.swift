import SwiftUI

struct iPad_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var selection: String? = nil // groupID
    @State private var showingAddGroup = false
    @State private var editingGroup: DeviceGroup? = nil
    @State private var editMode: EditMode = .inactive
    @State private var currentGroup: DeviceGroup? = nil // Track the currently displayed group

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text("groups")) {
                    ForEach(groupStore.groups) { group in
                        iPhone_GroupRowView(group: group)
                            .tag(group.id)
                            .contextMenu {
                                /*Button {
                                    editingGroup = group
                                } label: {
                                    Label("edit_group", systemImage: "pencil")
                                }*/
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
                iPad_GroupMapView(group: group)
                    .environmentObject(groupStore) // Pass the groupStore to the map view
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { editingGroup = groupStore.groups.first(where: { $0.id == selectedID }) }) {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                    .sheet(item: $editingGroup) { group in
                        iPhone_GroupDetailView(group: group)
                    }
                    .onChange(of: editingGroup) { _, newValue in
                        // When the editingGroup becomes nil (sheet is dismissed), 
                        // force a refresh of the map view
                        if newValue == nil {
                            // Trigger a refresh by temporarily clearing and restoring the selection
                            let currentSelection = selection
                            selection = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                selection = currentSelection
                            }
                        }
                    }
            } else if let firstGroup = groupStore.groups.first {
                // Automatically show the first group if no group is selected
                iPad_GroupMapView(group: firstGroup)
                    .environmentObject(groupStore)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { editingGroup = firstGroup }) {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                    .sheet(item: $editingGroup) { group in
                        iPhone_GroupDetailView(group: group)
                    }
                    .onChange(of: editingGroup) { _, newValue in
                        // When the editingGroup becomes nil (sheet is dismissed), 
                        // force a refresh of the map view
                        if newValue == nil {
                            // Trigger a refresh by temporarily clearing and restoring the selection
                            let currentSelection = selection
                            selection = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                selection = currentSelection
                            }
                        }
                    }
            } else {
                Text(NSLocalizedString("no_groups_available_create_new", comment: "No groups available. Create a new group to get started."))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
        }
        .onAppear {
            // Automatically select the first group if no group is currently selected
            if selection == nil && !groupStore.groups.isEmpty {
                selection = groupStore.groups.first?.id
            }
        }
    }
}

#Preview {
    iPad_GroupsView().environmentObject(DeviceGroupStore.shared)
} 
