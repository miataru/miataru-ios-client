/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_GroupsView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPad_GroupsView: View {
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var selection: String? = nil // groupID
    @State private var showingAddGroup = false
    @State private var editingGroup: DeviceGroup? = nil
    @State private var editMode: EditMode = .inactive
    @State private var currentGroup: DeviceGroup? = nil // Track the currently displayed group
    @State private var lastSelectedGroupID: String? = nil // Preserve selection across edit mode toggles

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text(NSLocalizedString("groups", comment: "Groups list header on iPad"))) {
                    ForEach(groupStore.groups) { group in
                        GroupRowView(group: group)
                            .tag(group.id)
                            .tint(.primary)
                            .contextMenu {
                                Button {
                                    editingGroup = group
                                } label: {
                                    Label(NSLocalizedString("edit_group", comment: "Edit this group."), systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    groupStore.remove(group: group)
                                } label: {
                                    Label("delete_group", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingGroup = group
                                } label: {
                                    Label(NSLocalizedString("edit_group", comment: "Edit this group."), systemImage: "pencil")
                                }
                                .tint(.blue)
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
            .navigationTitle(NSLocalizedString("groups", comment: "Groups list title on iPad"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        editMode = editMode == .active ? .inactive : .active
                    } label: {
                        if editMode == .active {
                            Text(NSLocalizedString("grouplist_edit_done", comment: "Finish editing the group list."))
                        } else {
                            Text(NSLocalizedString("grouplist_editbutton", comment: "Edit group list"))
                            //Image(systemName: "pencil")
                            //    .accessibilityLabel(Text(NSLocalizedString("grouplist_editbutton", comment: "Edit group list")))
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
            .environment(\.editMode, $editMode)
        } detail: {
            NavigationStack {
                let resolvedSelection = selection ?? lastSelectedGroupID ?? groupStore.groups.first?.id
                if let selectedID = resolvedSelection, let group = groupStore.groups.first(where: { $0.id == selectedID }) {
                    iPad_GroupMapView(group: group)
                        .environmentObject(groupStore) // Pass the groupStore to the map view
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(action: { editingGroup = groupStore.groups.first(where: { $0.id == selectedID }) }) {
                                    Label(NSLocalizedString("edit_group", comment: "Edit the selected group.."), systemImage: "pencil")
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                        .sheet(item: $editingGroup) { group in
                            NavigationStack {
                                iPad_GroupDetailView(group: group)
                            }
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
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $showingAddGroup) {
            iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
        }
        .onAppear {
            // Automatically select the first group if no group is currently selected
            if selection == nil && !groupStore.groups.isEmpty {
                let firstID = groupStore.groups.first?.id
                selection = firstID
                lastSelectedGroupID = firstID
            }
        }
        .onChange(of: selection) { _, newSelection in
            if let newSelection = newSelection, newSelection != lastSelectedGroupID {
                lastSelectedGroupID = newSelection
            }
        }
        .onChange(of: editMode) { _, newMode in
            // Restore previous selection when entering edit mode to avoid detail reset
            if newMode == .active {
                if selection == nil, let last = lastSelectedGroupID {
                    selection = last
                }
            }
        }
    }
}

#Preview {
    iPad_GroupsView().environmentObject(DeviceGroupStore.shared)
} 
