/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_AddGroupView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_AddGroupView: View {
    @ObservedObject var groupStore: DeviceGroupStore
    @Binding var isPresented: Bool
    @State private var groupName: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("group_name", tableName: "Groups")) {
                    TextField(String(localized: "group_name_placeholder", table: "Groups"), text: $groupName)
                }
            }
            .navigationTitle(String(localized: "add_new_group", table: "Groups"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel", table: "Common")) {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "add", table: "Common")) {
                        let newGroup = DeviceGroup(name: groupName)
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
    let groupStore = DeviceGroupStore.shared
    iPhone_AddGroupView(groupStore: groupStore, isPresented: .constant(true))
} 
