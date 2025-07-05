import SwiftUI

struct iPhone_GroupsView: View {
    @StateObject private var groupStore = DeviceGroupStore()
    @State private var showingAddGroup = false
    @State private var editMode: EditMode = .inactive

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
            .sheet(isPresented: $showingAddGroup) {
                iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
            }
        }
    }
}

#Preview {
    let groupStore = DeviceGroupStore()
    groupStore.groups = [
        DeviceGroup(name: "Family", color: .blue),
        DeviceGroup(name: "Work", color: .green),
        DeviceGroup(name: "Friends", color: .orange)
    ]
    return iPhone_GroupsView().environmentObject(groupStore)
} 
