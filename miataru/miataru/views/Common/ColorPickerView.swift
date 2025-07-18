import SwiftUI

/// A simple, reusable color picker view that mimics the basic functionality of SwiftUI's ColorPicker.
/// Displays a horizontal row of selectable color circles. Selection is passed via a Binding<Color>.
struct ColorPickerView: View {
    @Binding var selectedColor: Color
    
    // You can customize this palette as needed
    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .black, .gray, .white
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(colors, id: \.self) { color in
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == color ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                            .shadow(radius: 1)
                    }
                    .onTapGesture {
                        selectedColor = color
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
    }
}

/// Ein vollständiger ColorPicker-Sheet mit Palette, Hue- und Brightness-Slider
struct ColorPickerSheet: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss
    
    // Palette (kann angepasst werden)
    private let palette: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .black, .gray, .white
    ]
    
    // Interne HSB-Werte
    @State private var hue: Double = 0.0
    @State private var brightness: Double = 1.0
    
    // Initialisiert HSB aus der aktuellen Farbe
    private func updateHSB(from color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        brightness = Double(b)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("Pick Color", comment: "Title for color picker sheet"))
                .font(.headline)
            // Palette
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(palette, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == color ? Color.accentColor : Color.clear, lineWidth: 3)
                            )
                            .shadow(radius: 1)
                            .onTapGesture {
                                selectedColor = color
                                updateHSB(from: color)
                            }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
            // Vorschau
            Circle()
                .fill(selectedColor)
                .frame(width: 48, height: 48)
                .shadow(radius: 2)
                .padding(.top, 8)
            // Hue Slider
            VStack(alignment: .leading) {
                Text(NSLocalizedString("Hue", comment: "Label for hue slider in color picker"))
                    .font(.caption)
                Slider(value: $hue, in: 0...1, step: 0.01) {
                    Text(NSLocalizedString("Hue", comment: "Accessibility label for hue slider in color picker"))
                } minimumValueLabel: {
                   // text minimum
                } maximumValueLabel: {
                    // text maximum
                }
                .onChange(of: hue) {
                    selectedColor = Color(hue: hue, saturation: 1, brightness: brightness)
                }
            }
            // Brightness Slider
            VStack(alignment: .leading) {
                Text(NSLocalizedString("Brightness", comment: "Label for brightness slider in color picker"))
                    .font(.caption)
                Slider(value: $brightness, in: 0...1, step: 0.01) {
                    Text(NSLocalizedString("Brightness", comment: "Accessibility label for brightness slider in color picker"))
                } minimumValueLabel: {
                    // text minimum
                } maximumValueLabel: {
                    // text maximum
                }
                .onChange(of: brightness) {
                    selectedColor = Color(hue: hue, saturation: 1, brightness: brightness)
                }
            }
            // Fertig-Button
            Button(NSLocalizedString("Done", comment: "Button to close color picker sheet")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
        .onAppear {
            updateHSB(from: selectedColor)
        }
    }
}

// Beispiel: Button, der das Sheet öffnet
struct ColorPickerButtonDemo: View {
    @State private var color: Color = .red
    @State private var showSheet = false
    var body: some View {
        Button(action: { showSheet = true }) {
            HStack {
                Circle().fill(color).frame(width: 24, height: 24)
                Text(NSLocalizedString("Pick Color", comment: "Button label to open color picker sheet"))
            }
        }
        .sheet(isPresented: $showSheet) {
            ColorPickerSheet(selectedColor: $color)
        }
    }
}

// Preview aktualisieren
struct ColorPickerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            //StatefulPreviewWrapper(Color.red) { ColorPickerView(selectedColor: $0) }
            ColorPickerButtonDemo()
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

/// Helper for previewing with @Binding
struct StatefulPreviewWrapper<Value: Equatable & Hashable, Content: View>: View {
    @State private var value: Value
    var content: (Binding<Value>) -> Content
    
    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }
    
    var body: some View {
        content($value)
    }
}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

#Preview("ColorPickerView", traits: .sizeThatFitsLayout) {
    StatefulPreviewWrapper(Color.red) { ColorPickerView(selectedColor: $0) }
        .padding()
}

#Preview("ColorPickerSheet", traits: .sizeThatFitsLayout) {
    StatefulPreviewWrapper(Color.blue) { ColorPickerSheet(selectedColor: $0) }
        .padding()
}
#endif 
