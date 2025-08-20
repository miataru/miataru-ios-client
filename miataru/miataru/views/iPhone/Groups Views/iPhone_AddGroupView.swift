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
                Section(header: Text("group_name")) {
                    TextField("group_name_placeholder", text: $groupName)
                }
            }
            .navigationTitle("add_new_group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
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
