import SwiftUI

struct iPhone_MyDeviceQRCodeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone")
                .resizable()
                .frame(width: 80, height: 120)
                .foregroundColor(.blue)
            Text("my_device_qr_code")
                .font(.title)
            Text("qr_code_explanation")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("my_device")
    }
}

#Preview {
    iPhone_MyDeviceQRCodeView()
} 
