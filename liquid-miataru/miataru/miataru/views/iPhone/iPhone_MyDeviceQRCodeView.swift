import SwiftUI
import QRCode

struct iPhone_MyDeviceQRCodeView: View {
    @State var content: String = "miataru://" + thisDeviceIDManager.shared.deviceID
    @State var correction: QRCode.ErrorCorrection = .low

    @State var dataColor: Color = .primary
    @State var eyeColor: Color = .primary
    @State var pupilColor: Color = .primary
    @State var backgroundColor: Color = .clear

    @State var pixelShape: String = "square"
    @State var eyeStyle: String = "square"
    @State var pupilStyle: String = "square"

    @State var dataInset: Double = 0
    @State var cornerRadiusFraction: Double = 0.5
    @State var rotationFraction: Double = 0.0

        let gradient = Gradient(colors: [.black, .pink])
    var body: some View {
        let qrContent = QRCodeShape(
                    data: content.data(using: .utf8) ?? Data(),
                    errorCorrection: correction
                )
        
        VStack(spacing: 20) {
            ZStack {
                                backgroundColor
                                qrContent
                                    .components(.eyeOuter)
                                    .fill(eyeColor)
                                qrContent
                                    .components(.eyePupil)
                                    .fill(pupilColor)
                                qrContent
                                    .components(.onPixels)
                                    .fill(dataColor)
                            }
                            .frame(width: 250, height: 250, alignment: .center)
                            .padding()
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
