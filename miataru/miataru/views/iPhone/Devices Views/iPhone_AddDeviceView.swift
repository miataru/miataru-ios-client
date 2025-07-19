import SwiftUI
import CodeScanner

struct iPhone_AddDeviceView: View {
    @ObservedObject var store: KnownDeviceStore
    @Binding var isPresented: Bool
    var prefillDeviceID: String? = nil
    @State private var deviceName: String = ""
    @State private var deviceID: String = ""
    @State private var deviceColor: Color = .gray
    @State private var isShowingScanner = false
    @State private var showInvalidQRAlert = false
    @State private var showDuplicateAlert = false
    @State private var showColorPickerSheet = false
    
    init(store: KnownDeviceStore, isPresented: Binding<Bool>, prefillDeviceID: String? = nil) {
        self.store = store
        self._isPresented = isPresented
        self.prefillDeviceID = prefillDeviceID
        if let prefill = prefillDeviceID {
            _deviceID = State(initialValue: prefill)
        }
    }
    
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
                    Button(action: { showColorPickerSheet = true }) {
                        HStack {
                            Circle().fill(deviceColor).frame(width: 24, height: 24)
                            Text(NSLocalizedString("Pick Color", comment: "Button label to open color picker sheet"))
                        }
                    }
                    .sheet(isPresented: $showColorPickerSheet) {
                        ColorPickerSheet(selectedColor: $deviceColor)
                            .presentationDetents([.medium])
                    }
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
                        let success = store.add(device: newDevice)
                        if success {
                            isPresented = false
                        } else {
                            showDuplicateAlert = true
                        }
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
        .alert(isPresented: $showDuplicateAlert) {
            Alert(
                title: Text(NSLocalizedString("adddevice_duplicate_device_id_title", comment: "Alert title shown when user tries to add a duplicate device.")),
                message: Text(NSLocalizedString("adddevice_duplicate_device_already_exists_message", comment:"Alert text shown when user tries to add a duplicate device.")),
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
