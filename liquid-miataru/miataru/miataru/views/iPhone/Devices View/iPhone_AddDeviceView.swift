import SwiftUI

struct iPhone_AddDeviceView: View {
    @ObservedObject var store: KnownDeviceStore
    @Binding var isPresented: Bool
    @State private var deviceName: String = ""
    @State private var deviceID: String = ""
    @State private var deviceColor: Color = .gray
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $deviceName)
                }
                Section(header: Text("device_id")) {
                    TextField("device_id2", text: $deviceID)
                }
                Section(header: Text("device_color")) {
                    ColorPicker("device_color2", selection: $deviceColor)
                }
            }
            .navigationTitle("new_device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
                        let uiColor = UIColor(deviceColor)
                        let newDevice = KnownDevice(name: deviceName, deviceID: deviceID, color: uiColor)
                        store.add(device: newDevice)
                        isPresented = false
                    }
                    .disabled(deviceName.isEmpty || deviceID.isEmpty)
                }
            }
        }
    }
} 
