import SwiftUI

struct iPhone_EditDeviceView: View {
    @Binding var device: KnownDevice
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $device.DeviceName)
                }
                Section(header: Text("device_id")) {
                    TextField("device_id2", text: .constant(device.DeviceID))
                        .disabled(true) // DeviceID sollte nicht editierbar sein
                }
                Section(header: Text("device_color")) {
                    ColorPicker("device_color2", selection: Binding(
                        get: {
                            if #available(iOS 14.0, *) {
                                return Color(device.DeviceColor ?? UIColor.gray)
                            } else {
                                return .gray
                            }
                        },
                        set: { newColor in
                            if #available(iOS 14.0, *) {
                                device.DeviceColor = UIColor(newColor)
                            }
                        }
                    ))
                }
            }
            .navigationTitle("edit_device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        isPresented = false
                    }
                    .disabled(device.DeviceName.isEmpty)
                }
            }
        }
    }
} 
