import SwiftUI
import CodeScanner

struct iPhone_AddDeviceView: View {
    @ObservedObject var store: KnownDeviceStore
    @Binding var isPresented: Bool
    @State private var deviceName: String = ""
    @State private var deviceID: String = ""
    @State private var deviceColor: Color = .gray
    @State private var isShowingScanner = false
    @State private var showInvalidQRAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $deviceName)
                }
                Section(header: Text("device_id")) {
                    Button(action: { isShowingScanner = true }) {
                        Label("scan_qr_code", systemImage: "qrcode.viewfinder")
                    }
                    TextField("device_id2", text: $deviceID)
                }
                Section(header: Text("device_color")) {
                    ColorPicker("device_colorpicker", selection: $deviceColor)
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
        .sheet(isPresented: $isShowingScanner) {
            CodeScannerView(codeTypes: [.qr]) { result in
                switch result {
                case .success(let res):
                    let prefix = "miataru://"
                    if res.string.hasPrefix(prefix) {
                        deviceID = String(res.string.dropFirst(prefix.count)).uppercased()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingScanner = false
                        }
                    } else {
                        deviceID = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingScanner = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                showInvalidQRAlert = true
                            }
                        }
                    }
                case .failure:
                    isShowingScanner = false
                }
            }
        }
        .alert(isPresented: $showInvalidQRAlert) {
            Alert(
                title: Text("invalid_miataru_qr_code"),
                message: Text("invalid_miataru_qr_code_error_text"), //"Der QR-Code muss mit 'miataru://' beginnen."
                dismissButton: .default(Text("ok"))
            )
        }
    }
}

#if DEBUG
struct iPhone_AddDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        // Beispiel-Daten für die Vorschau
        let store = KnownDeviceStore.shared
        iPhone_AddDeviceView(store: store, isPresented: .constant(true))
    }
}
#endif 
