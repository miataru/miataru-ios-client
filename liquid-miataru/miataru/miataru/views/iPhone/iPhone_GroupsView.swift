import SwiftUI

struct iPhone_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var showingAddGroup = false
    @State private var editMode: EditMode = .inactive
    @State private var editingGroup: DeviceGroup? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(groupStore.groups) { group in
                    NavigationLink(destination: iPhone_GroupDetailView(group: group)) {
                        iPhone_GroupRowView(group: group)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) {
                                groupStore.remove(atOffsets: IndexSet(integer: index))
                            }
                        } label: {
                            Label("delete_group", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editingGroup = group
                        } label: {
                            Label("edit_group", systemImage: "pencil")
                        }
                        .tint(.blue)
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
                iPhone_EditGroupNameView(group: group, isPresented: Binding(
                    get: { editingGroup != nil },
                    set: { if !$0 { editingGroup = nil } }
                ))
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
