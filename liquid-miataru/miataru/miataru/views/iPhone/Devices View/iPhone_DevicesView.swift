import SwiftUI

struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore()
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var deviceToEdit: KnownDevice? = nil
    @State private var isEditing = false

    var body: some View {
        NavigationView {
            List {
                ForEach(store.devices, id: \.DeviceID) { device in
                    DeviceRowView(device: device)
                        .swipeActions(edge: .trailing) {
                            Button {
                                deviceToEdit = device
                                showEditSheet = true
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
                .onMove { indices, newOffset in
                    store.devices.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .navigationTitle("devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showAddSheet = true }) {
                            Image(systemName: "plus")
                        }
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, .constant(isEditing ? EditMode.active : EditMode.inactive))
            .sheet(isPresented: $showAddSheet) {
                DeviceEditView(store: store, device: nil)
            }
            .sheet(item: $deviceToEdit) { device in
                DeviceEditView(store: store, device: device)
            }
        }
    }
} 

#Preview {
    iPhone_DevicesView()
} 
