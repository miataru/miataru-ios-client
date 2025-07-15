import SwiftUI
enum MiataruPalette {
    static let background_color = Color(red: 22/255, green: 55/255, blue: 72/255, opacity: 1.0)
    static let layer1_color = Color.white
    static let layer2_color = Color(red: 88/255, green: 165/255, blue: 203/255, opacity: 1.0)
    static let layer3_color = Color(red: 52/255, green: 126/255, blue: 164/255, opacity: 1.0)
    static let layer4_color = Color(red: 41/255, green: 98/255, blue: 127/255, opacity: 1.0)
}

struct MiataruIcon_Layer4: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.55164*width, y: 0.01972*height))
        path.addCurve(to: CGPoint(x: 0.55013*width, y: 1.0196*height), control1: CGPoint(x: 1.41011*width, y: 0.01867*height), control2: CGPoint(x: 0.98552*width, y: 1.02003*height))
        path.addCurve(to: CGPoint(x: 0.55164*width, y: 0.01972*height), control1: CGPoint(x: 0.11561*width, y: 1.01497*height), control2: CGPoint(x: -0.31909*width, y: 0.02079*height))
        path.closeSubpath()
        return path
    }
}

struct MiataruIcon_Layer3: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.55107*width, y: 0.06424*height))
        path.addCurve(to: CGPoint(x: 0.54984*width, y: 1.01972*height), control1: CGPoint(x: 1.24688*width, y: 0.06323*height), control2: CGPoint(x: 0.90273*width, y: 1.02013*height))
        path.addCurve(to: CGPoint(x: 0.55107*width, y: 0.06424*height), control1: CGPoint(x: 0.19765*width, y: 1.0153*height), control2: CGPoint(x: -0.15469*width, y: 0.06525*height))
        path.closeSubpath()
        return path
    }
}


struct MiataruIcon_Layer2: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.52872*width, y: 0.98926*height))
        path.addCurve(to: CGPoint(x: 0.24747*width, y: 0.54424*height), control1: CGPoint(x: 0.4137*width, y: 0.85498*height), control2: CGPoint(x: 0.3046*width, y: 0.71046*height))
        path.addCurve(to: CGPoint(x: 0.28852*width, y: 0.2361*height), control1: CGPoint(x: 0.21508*width, y: 0.4423*height), control2: CGPoint(x: 0.2225*width, y: 0.3249*height))
        path.addCurve(to: CGPoint(x: 0.59028*width, y: 0.10469*height), control1: CGPoint(x: 0.35298*width, y: 0.14359*height), control2: CGPoint(x: 0.47332*width, y: 0.08538*height))
        path.addCurve(to: CGPoint(x: 0.86483*width, y: 0.42616*height), control1: CGPoint(x: 0.74928*width, y: 0.1262*height), control2: CGPoint(x: 0.8731*width, y: 0.27433*height))
        path.addCurve(to: CGPoint(x: 0.71184*width, y: 0.80616*height), control1: CGPoint(x: 0.86082*width, y: 0.56521*height), control2: CGPoint(x: 0.78779*width, y: 0.69121*height))
        path.addCurve(to: CGPoint(x: 0.5498*width, y: 1.01158*height), control1: CGPoint(x: 0.66289*width, y: 0.87809*height), control2: CGPoint(x: 0.60778*width, y: 0.94606*height))
        path.addCurve(to: CGPoint(x: 0.52872*width, y: 0.98926*height), control1: CGPoint(x: 0.54277*width, y: 1.00414*height), control2: CGPoint(x: 0.53575*width, y: 0.9967*height))
        path.closeSubpath()

        return path
    }
}

struct MiataruIcon_Layer1: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.67506*width, y: 0.32852*height))
        path.addCurve(to: CGPoint(x: 0.54431*width, y: 0.71084*height), control1: CGPoint(x: 0.63148*width, y: 0.45596*height), control2: CGPoint(x: 0.58789*width, y: 0.5834*height))
        path.addCurve(to: CGPoint(x: 0.53249*width, y: 0.67969*height), control1: CGPoint(x: 0.53878*width, y: 0.70255*height), control2: CGPoint(x: 0.5367*width, y: 0.68973*height))
        path.addCurve(to: CGPoint(x: 0.41239*width, y: 0.32919*height), control1: CGPoint(x: 0.49245*width, y: 0.56286*height), control2: CGPoint(x: 0.45242*width, y: 0.44602*height))
        path.addCurve(to: CGPoint(x: 0.36293*width, y: 0.64937*height), control1: CGPoint(x: 0.3959*width, y: 0.43591*height), control2: CGPoint(x: 0.37942*width, y: 0.54264*height))
        path.addCurve(to: CGPoint(x: 0.2811*width, y: 0.64937*height), control1: CGPoint(x: 0.33565*width, y: 0.64937*height), control2: CGPoint(x: 0.30837*width, y: 0.64937*height))
        path.addCurve(to: CGPoint(x: 0.38206*width, y: 0.15441*height), control1: CGPoint(x: 0.31475*width, y: 0.48438*height), control2: CGPoint(x: 0.34841*width, y: 0.3194*height))
        path.addCurve(to: CGPoint(x: 0.44244*width, y: 0.15441*height), control1: CGPoint(x: 0.40219*width, y: 0.15441*height), control2: CGPoint(x: 0.42231*width, y: 0.15441*height))
        path.addCurve(to: CGPoint(x: 0.54393*width, y: 0.49846*height), control1: CGPoint(x: 0.47627*width, y: 0.26909*height), control2: CGPoint(x: 0.5101*width, y: 0.38377*height))
        path.addCurve(to: CGPoint(x: 0.64426*width, y: 0.15586*height), control1: CGPoint(x: 0.57737*width, y: 0.38426*height), control2: CGPoint(x: 0.61082*width, y: 0.27006*height))
        path.addCurve(to: CGPoint(x: 0.70544*width, y: 0.15586*height), control1: CGPoint(x: 0.66465*width, y: 0.15586*height), control2: CGPoint(x: 0.68505*width, y: 0.15586*height))
        path.addCurve(to: CGPoint(x: 0.80456*width, y: 0.64719*height), control1: CGPoint(x: 0.73848*width, y: 0.31964*height), control2: CGPoint(x: 0.77152*width, y: 0.48341*height))
        path.addCurve(to: CGPoint(x: 0.72273*width, y: 0.64719*height), control1: CGPoint(x: 0.77728*width, y: 0.64719*height), control2: CGPoint(x: 0.75*width, y: 0.64719*height))
        path.addCurve(to: CGPoint(x: 0.67506*width, y: 0.32852*height), control1: CGPoint(x: 0.70684*width, y: 0.54097*height), control2: CGPoint(x: 0.69095*width, y: 0.43474*height))
        path.closeSubpath()
        return path
    }
}


struct MiataruIcon: View {
    var body: some View {
        ZStack {
            MiataruIcon_Layer4().fill(MiataruPalette.layer4_color)
            MiataruIcon_Layer3().fill(MiataruPalette.layer3_color).shadow(radius: 2)
            MiataruIcon_Layer2().fill(MiataruPalette.layer2_color).shadow(radius: 2)
            MiataruIcon_Layer1().fill(MiataruPalette.layer1_color).shadow(radius: 1)
        }.scaledToFit().shadow(radius: 8)
    }
}

