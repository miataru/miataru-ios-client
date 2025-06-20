import SwiftUI

struct MyDeviceQRCodeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone")
                .resizable()
                .frame(width: 80, height: 120)
                .foregroundColor(.blue)
            Text("Mein Gerät")
                .font(.title)
            Text("Geräteinformationen anzeigen")
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Mein Gerät")
    }
}

#Preview {
    MyDeviceQRCodeView()
} 
