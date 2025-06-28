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
    
    @State private var showCopiedAlert = false

    let gradient = Gradient(colors: [.black, .pink])
    
    var body: some View {
        let qrContent = QRCodeShape(
                    data: content.data(using: .utf8) ?? Data(),
                    errorCorrection: correction
                )
        
        ZStack {
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
                
                // Device-ID Anzeige mit Kopier-Button
                VStack(spacing: 12) {
                    Text("device_id")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Text(thisDeviceIDManager.shared.deviceID)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        Button(action: {
                            UIPasteboard.general.string = thisDeviceIDManager.shared.deviceID
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showCopiedAlert = true
                            }
                            
                            // Alert nach 2 Sekunden automatisch ausblenden
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCopiedAlert = false
                                }
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 10)
            }
            .padding()
            .navigationTitle("my_device")
            
            // Overlay für Kopier-Bestätigung
            if showCopiedAlert {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        Text("device_id_copied_to_clipboard")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.8))
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .zIndex(1)
            }
        }
    }
}

#Preview {
    iPhone_MyDeviceQRCodeView()
} 
