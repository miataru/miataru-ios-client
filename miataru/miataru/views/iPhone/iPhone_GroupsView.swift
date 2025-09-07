/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_GroupsView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var showingAddGroup = false
    @State private var editMode: EditMode = .inactive
    @State private var editingGroup: DeviceGroup? = nil
    @State private var selectedGroupID: String? = nil

    var body: some View {
        NavigationStack {
            // iOS 26: transparent background, iOS prior: ultrathin material
            if groupStore.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("No groups yet", comment: "Shown when there are no groups in the list"))
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("Tap the + button to create a new group.", comment: "Instruction to create a new group when none exist"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(NSLocalizedString("groups", comment: "Navigation title for the groups list"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            editMode = editMode == .active ? .inactive : .active
                        } label: {
                            if editMode == .active {
                                Text(NSLocalizedString("grouplist_edit_done", comment: "Finish editing the groups list."))
                            } else {
                                Image(systemName: "pencil")
                                    .accessibilityLabel(Text(NSLocalizedString("grouplist_editbutton", comment: "Edit groups list")))
                                    .accessibilityHint(Text(NSLocalizedString("grouplist_editbutton_hint", comment: "Enters edit mode for the groups list")))
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddGroup = true }) {
                            Image(systemName: "plus")
                                .accessibilityLabel(Text(NSLocalizedString("grouplist_addbutton", comment: "Create a new group")))
                                .accessibilityHint(Text(NSLocalizedString("grouplist_addbutton_hint", comment: "Opens the create group sheet")))
                        }
                    }
                }
                .sheet(isPresented: $showingAddGroup) {
                    iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
                }
            } else {
                List {
                    ForEach(groupStore.groups) { group in
                        NavigationLink(value: group.id) {
                            GroupRowView(group: group)
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
                        .swipeActions(edge: .leading) {
                            Button {
                                editingGroup = group
                                selectedGroupID = group.id
                            } label: {
                                Label {
                                    Text(NSLocalizedString("edit_group", comment: "Edit group"))
                                } icon: {
                                    Image(systemName: "pencil")
                                }
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
                .navigationTitle(NSLocalizedString("groups", comment: "Navigation title for the groups list"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            editMode = editMode == .active ? .inactive : .active
                        } label: {
                            if editMode == .active {
                                Text(NSLocalizedString("grouplist_edit_done", comment: "Finish editing the groups list."))
                            } else {
                                Image(systemName: "pencil")
                                    .accessibilityLabel(Text(NSLocalizedString("grouplist_editbutton", comment: "Edit groups list")))
                                    .accessibilityHint(Text(NSLocalizedString("grouplist_editbutton_hint", comment: "Enters edit mode for the groups list")))
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddGroup = true }) {
                            Image(systemName: "plus")
                                .accessibilityLabel(Text(NSLocalizedString("grouplist_addbutton", comment: "Create a new group")))
                                .accessibilityHint(Text(NSLocalizedString("grouplist_addbutton_hint", comment: "Opens the create group sheet")))
                        }
                    }
                }
                .sheet(isPresented: $showingAddGroup) {
                    iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
                }
                .sheet(item: $editingGroup) { group in
                    GroupEditSheetContainer(group: group) {
                        editingGroup = nil
                        selectedGroupID = nil
                    } onSave: {
                        editingGroup = nil
                        selectedGroupID = nil
                    }
                }
                .navigationDestination(for: String.self) { groupID in
                    if let group = groupStore.groups.first(where: { $0.id == groupID }) {
                        iPhone_GroupMapView(group: group)
                    } else {
                        Text(NSLocalizedString("Group not found", comment: "Shown when a group with the given ID does not exist"))
                    }
                }
                .onChange(of: selectedGroupID) {
                    // Optional: handle side effects if needed
                }
                .onChange(of: editingGroup) {
                    if editingGroup == nil {
                        selectedGroupID = nil
                    }
                }
            }
        }
        .adaptiveNavigationBackground()
    }
}

// MARK: - Group Edit Sheet Container

struct GroupEditSheetContainer: View {
    @ObservedObject var group: DeviceGroup
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var originalGroupName: String = ""
    @State private var originalDeviceIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            iPhone_GroupDetailView(group: group, showsDoneButton: false)
                .navigationTitle(group.groupName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "Cancel editing the group")) {
                            group.groupName = originalGroupName
                            group.deviceIDs = originalDeviceIDs
                            dismiss()
                            onCancel()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("save", comment: "Save changes to the group")) {
                            dismiss()
                            onSave()
                        }
                    }
                }
                .onAppear {
                    originalGroupName = group.groupName
                    originalDeviceIDs = group.deviceIDs
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
