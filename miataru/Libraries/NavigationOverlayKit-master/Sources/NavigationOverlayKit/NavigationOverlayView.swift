import SwiftUI
import MapKit

/// A SwiftUI overlay view that displays the current navigation instruction alongside distance information.
/// 
/// This view provides a modern, translucent overlay that shows:
/// - Navigation direction icon with gradient background
/// - Text instruction for the current maneuver
/// - Remaining distance to the next waypoint
/// 
/// The overlay uses iOS material effects and glass morphism for a polished appearance,
/// with smooth animations when transitioning between instructions.
public struct NavigationOverlayView: View {
    /// The view model that manages navigation state and instruction updates
    @ObservedObject private var viewModel: NavigationOverlayViewModel
    
    /// The alignment of the overlay within its parent view (defaults to top)
    private let alignment: Alignment
    
    /// Whether wheelchair accessibility mode is enabled
    private let isWheelchairAccessible: Bool

    /// Initializes the navigation overlay view
    /// - Parameters:
    ///   - viewModel: The view model containing navigation state and instructions
    ///   - alignment: The alignment of the overlay (defaults to `.top`)
    ///   - isWheelchairAccessible: Whether wheelchair accessibility mode is enabled (defaults to `false`)
    public init(viewModel: NavigationOverlayViewModel, alignment: Alignment = .top, isWheelchairAccessible: Bool = false) {
        self.viewModel = viewModel
        self.alignment = alignment
        self.isWheelchairAccessible = isWheelchairAccessible
    }

    /// The main body of the navigation overlay view
    /// 
    /// Creates a ZStack with conditional content that only displays when an instruction is available.
    /// Includes smooth spring animations for instruction transitions and opacity/movement effects.
    public var body: some View {
        ZStack(alignment: alignment) {
            // Only show overlay content when there's an active instruction
            if let instruction = viewModel.instruction {
                overlayContent(for: instruction)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding()
            }
        }
        // Smooth spring animation for instruction changes
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.instruction)
    }

    /// Creates the main content layout for the navigation overlay
    /// 
    /// Builds a horizontal stack containing:
    /// - Direction icon with gradient background and shadow
    /// - Vertical stack with instruction text and distance information
    /// 
    /// - Parameter instruction: The navigation instruction to display
    /// - Returns: A view containing the formatted overlay content
    @ViewBuilder
    private func overlayContent(for instruction: NavigationInstruction) -> some View {
        HStack(spacing: 18) {
            // Direction icon with gradient background
            Image(systemName: instruction.symbol.systemImageName(isWheelchairAccessible: isWheelchairAccessible))
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
                .background(directionIconBackground(
                    progress: fillProgress(
                        remainingDistance: viewModel.remainingDistance ?? instruction.distance,
                        totalDistance: instruction.distance
                    )
                ))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 6)

            // Text content stack
            VStack(alignment: .leading, spacing: 6) {
                // Main instruction text
                Text(instruction.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)

                // Distance information (uses remaining distance if available, otherwise instruction distance)
                Text(distanceText(for: viewModel.remainingDistance ?? instruction.distance))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: 380)
        .background(tintedOverlayBackground())
        .padding([.horizontal, .top])
    }

    /// Creates a gradient-outlined background whose fill represents remaining distance
    /// 
    /// - Parameter progress: A value in [0,1] indicating how much of the background should be filled
    ///   from the bottom (0 = empty at far distance, 1 = fully filled at 0 distance).
    /// - Returns: A view with a gradient stroke outline and a bottom-up fill bar.
    @ViewBuilder
    private func directionIconBackground(progress: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let outline = LinearGradient(
            colors: [
                Color.accentColor.opacity(0.85),
                Color.accentColor.opacity(0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        GeometryReader { proxy in
            let height = proxy.size.height
            let clamped = max(0, min(1, progress))
            let filledHeight = height * clamped

            ZStack(alignment: .bottom) {
                // Base background (liquid glass on iOS 26+)
                Group {
                    if #available(iOS 26.0, *) {
                        Color.clear
                            .glassEffect(in: .rect(cornerRadius: 18))
                    } else {
                        Color.clear
                    }
                }

                // Bottom-up fill representing progress (remaining distance -> 0 = 100%)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(height: filledHeight)
            }
            .clipShape(shape)
            //.overlay(shape.strokeBorder(outline, lineWidth: 2))
        }
        .animation(.easeInOut(duration: 0.25), value: progress)
    }

    /// Computes the bottom-up fill progress given remaining and total distances
    /// Progress = 1 - clamp(remaining / total, 0...1)
    private func fillProgress(
        remainingDistance: Measurement<UnitLength>,
        totalDistance: Measurement<UnitLength>
    ) -> CGFloat {
        let total = max(0.0, totalDistance.converted(to: .meters).value)
        let remaining = remainingDistance.converted(to: .meters).value
        guard total > 0 else { return remaining <= 0 ? 1.0 : 0.0 }
        let ratio = max(0.0, min(1.0, remaining / total))
        let progress = 1.0 - ratio
        return CGFloat(progress)
    }

    /// Creates the translucent background for the overlay with material effects
    /// 
    /// Provides different visual treatments based on the target environment:
    /// - Simulator: Uses ultra-thin material with tint overlay
    /// - iOS 26+: Uses glass morphism effect with enhanced shadows
    /// - Earlier iOS versions: Uses ultra-thin material with standard styling
    /// 
    /// - Returns: A styled background view with appropriate material effects
    @ViewBuilder
    private func tintedOverlayBackground() -> some View {
        let cornerRadius: CGFloat = 28
        if #available(iOS 26.0, *) {
            // iOS 26+ liquid glass effect, mirroring MapScaleBar implementation
            Color.clear
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            // Pre-iOS 26 fallback to ultraThinMaterial with rounded corners
            Color.clear
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Formats a distance measurement into a localized string
    /// 
    /// Converts the distance measurement to a user-friendly format using the system's
    /// measurement formatter with appropriate unit abbreviations and precision.
    /// 
    /// - Parameter distance: The distance measurement to format
    /// - Returns: A localized string representation of the distance
    private func distanceText(for distance: Measurement<UnitLength>) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.numberFormatter.minimumFractionDigits = 0
        return formatter.string(from: distance)
    }
}

#if DEBUG
/// Preview provider for SwiftUI development and testing
struct NavigationOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationOverlayView(viewModel: demoViewModel, isWheelchairAccessible: false)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.black)
    }

    /// Creates a demo view model with sample navigation instruction for preview purposes
    private static var demoViewModel: NavigationOverlayViewModel {
        let viewModel = NavigationOverlayViewModel()
        viewModel.update(with: NavigationInstruction(text: "Turn right onto Market Street", distance: Measurement(value: 120, unit: .meters), symbol: .right))
        return viewModel
    }
}
#endif
