import SwiftUI

struct iPhone_DeviceEditView: View {
    @ObservedObject var store: KnownDeviceStore
    @Environment(\.presentationMode) var presentationMode
    @State private var name: String = ""
    @State private var deviceID: String = ""
    @State private var color: Color = .gray
    var device: KnownDevice?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("Gerätename", text: $name)
                }
                Section(header: Text("Device ID")) {
                    TextField("Device ID", text: $deviceID)
                }
                Section(header: Text("Farbe")) {
                    ColorPicker("Farbe wählen", selection: $color)
                }
            }
            .navigationTitle(device == nil ? "Gerät hinzufügen" : "Gerät bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(device == nil ? "Hinzufügen" : "Speichern") {
                        if let device = device {
                            // Bearbeiten
                            device.DeviceName = name
                            device.DeviceID = deviceID
                            device.DeviceColor = UIColor(color)
                        } else {
                            // Hinzufügen
                            let newDevice = KnownDevice(name: name, deviceID: deviceID, color: UIColor(color))
                            store.devices.append(newDevice)
                        }
                        presentationMode.wrappedValue.dismiss()
                    }.disabled(name.isEmpty || deviceID.isEmpty)
                }
            }
        }
        .onAppear {
            if let device = device {
                name = device.DeviceName
                deviceID = device.DeviceID
                color = Color(device.DeviceColor ?? UIColor.gray)
            }
        }
    }
}

extension UIColor {
    convenience init(_ color: Color) {
        let uiColor = UIColor(color)
        self.init(cgColor: uiColor.cgColor)
    }
} 
