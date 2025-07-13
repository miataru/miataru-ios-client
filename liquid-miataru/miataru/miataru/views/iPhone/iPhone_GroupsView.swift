import SwiftUI

struct iPhone_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var showingAddGroup = false
    @State private var editMode: EditMode = .inactive
    @State private var editingGroup: DeviceGroup? = nil
    @State private var selectedGroupID: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupStore.groups) { group in
                    NavigationLink(value: group.id) {
                        iPhone_GroupRowView(group: group)
                    }
                    .listRowBackground(selectedGroupID == group.id ? Color(.systemGray) : Color(.systemBackground))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) {
                                groupStore.remove(atOffsets: IndexSet(integer: index))
                            }
                        } label: {
                            Label("delete_group", systemImage: "trash")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    groupStore.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indices in
                    groupStore.remove(atOffsets: indices)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGroup = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
            }
            .sheet(item: $editingGroup) { group in
                iPhone_GroupDetailView(group: group)
            }
            .navigationDestination(for: String.self) { groupID in
                if let group = groupStore.groups.first(where: { $0.id == groupID }) {
                    iPhone_GroupMapView(group: group)
                } else {
                    Text("Group not found")
                }
            }
            .onChange(of: selectedGroupID) { newValue in
                // Optional: handle side effects if needed
            }
        }
    }
}

#Preview {
    let groupStore = DeviceGroupStore.shared
    groupStore.groups = [
        DeviceGroup(name: "Family"),
        DeviceGroup(name: "Work"),
        DeviceGroup(name: "Friends")
    ]
    return iPhone_GroupsView().environmentObject(groupStore)
} 
