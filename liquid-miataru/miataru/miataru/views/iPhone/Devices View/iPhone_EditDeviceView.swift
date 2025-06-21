import SwiftUI

struct iPhone_EditDeviceView: View {
    @Binding var device: KnownDevice
    @Binding var isPresented: Bool
    @State private var copiedIDFeedback = false
    @State private var tempDeviceName: String = ""
    @State private var tempDeviceColor: Color = .gray

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $tempDeviceName)
                }
                Section(header: Text("device_id")) {
                    HStack {
                        Text(device.DeviceID)
                            .foregroundColor(.secondary)
                            .font(.body)
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = device.DeviceID
                            copiedIDFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedIDFeedback = false
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                Section(header: Text("device_color")) {
                    ColorPicker("device_color2", selection: $tempDeviceColor)
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
                        device.DeviceName = tempDeviceName
                        if #available(iOS 14.0, *) {
                            device.DeviceColor = UIColor(tempDeviceColor)
                        }
                        isPresented = false
                    }
                    .disabled(tempDeviceName.isEmpty)
                }
            }
            .onAppear {
                tempDeviceName = device.DeviceName
                if #available(iOS 14.0, *) {
                    tempDeviceColor = Color(device.DeviceColor ?? UIColor.gray)
                }
            }
        }
        .overlay(
            Group {
                if copiedIDFeedback {
                    Text("device_id_copied_to_clipboard")
                        .padding(12)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }, alignment: .top
        )
        .animation(.easeInOut, value: copiedIDFeedback)
    }
} 
