import Combine
import Foundation
import MapKit

/// Observes changes to the user's navigation progress and updates the overlay accordingly.
/// 
/// This view model manages the state of navigation instructions and remaining distances,
/// providing methods to advance through route steps and update the displayed information.
/// It acts as the bridge between MapKit route data and the SwiftUI navigation overlay.
public final class NavigationOverlayViewModel: ObservableObject {
    /// The current navigation instruction to display in the overlay
    @Published public private(set) var instruction: NavigationInstruction?

    /// The current instruction symbol, useful for reacting to specific maneuvers
    @Published public private(set) var symbol: NavigationInstruction.Symbol?
    
    /// The remaining distance to the destination (may differ from instruction distance)
    @Published public private(set) var remainingDistance: Measurement<UnitLength>?

    /// The MapKit route containing all navigation steps
    private let route: MKRoute?
    
    /// The preferred unit for distance measurements
    private let unit: UnitLength

    /// The index of the currently displayed route step
    private var currentStepIndex: Int

    /// Initializes the navigation overlay view model
    /// 
    /// - Parameters:
    ///   - route: Optional MapKit route containing navigation steps
    ///   - unit: The preferred unit for distance measurements (defaults to meters)
    public init(route: MKRoute? = nil, unit: UnitLength = .meters) {
        self.route = route
        self.unit = unit
        self.currentStepIndex = 0
        
        // Initialize with the first step if a route is provided
        if let route {
            updateInstruction(stepIndex: currentStepIndex, route: route)
        }
    }

    /// Advances the displayed instruction to the next step in the route
    /// 
    /// Moves to the next navigation step and updates both the instruction
    /// and remaining distance. This is typically called when the user
    /// completes the current maneuver.
    public func advance() {
        guard let route else { return }
        let nextIndex = currentStepIndex + 1
        updateInstruction(stepIndex: nextIndex, route: route)
    }

    /// Updates the instruction to a specific step index
    /// 
    /// Allows jumping to any step in the route, useful for scenarios like
    /// rerouting or when the user manually selects a different step.
    /// 
    /// - Parameter index: The index of the route step that should be displayed
    public func update(step index: Int) {
        guard let route else { return }
        updateInstruction(stepIndex: index, route: route)
    }

    /// Updates the view model with a completely new instruction
    /// 
    /// This method is used when providing custom navigation instructions
    /// that don't come from a MapKit route, such as manual directions
    /// or external navigation data.
    /// 
    /// - Parameter instruction: The instruction to display
    public func update(with instruction: NavigationInstruction) {
        self.instruction = instruction
        self.symbol = instruction.symbol
        self.remainingDistance = nil
    }

    /// Updates only the remaining distance shown in the overlay
    /// 
    /// Allows updating the distance information without changing the
    /// current instruction or symbol. Useful for real-time distance
    /// updates during navigation.
    /// 
    /// - Parameter distance: The distance to display
    public func updateRemainingDistance(to distance: Measurement<UnitLength>) {
        self.remainingDistance = distance
    }

    /// Updates the instruction and remaining distance for a specific route step
    /// 
    /// Internal method that handles the core logic of updating the view model
    /// state when advancing through route steps. Validates the step index
    /// and updates both instruction and remaining distance.
    /// 
    /// - Parameters:
    ///   - stepIndex: The index of the step to display
    ///   - route: The MapKit route containing the steps
    private func updateInstruction(stepIndex: Int, route: MKRoute) {
        guard route.steps.indices.contains(stepIndex) else { return }
        currentStepIndex = stepIndex
        instruction = NavigationInstruction.from(route: route, currentStepIndex: stepIndex, unit: unit)
        symbol = instruction?.symbol
        remainingDistance = calculateRemainingDistance(from: stepIndex, route: route)
    }

    /// Calculates the total remaining distance from a specific step to the end of the route
    /// 
    /// Sums up the distances of all steps from the given index to the end of the route,
    /// converting the result to the preferred unit.
    /// 
    /// - Parameters:
    ///   - index: The starting step index
    ///   - route: The MapKit route containing the steps
    /// - Returns: The total remaining distance as a measurement
    private func calculateRemainingDistance(from index: Int, route: MKRoute) -> Measurement<UnitLength> {
        let remainingMeters = route.steps[index...].reduce(0) { partialResult, step in
            partialResult + step.distance
        }
        return Measurement(value: remainingMeters, unit: UnitLength.meters).converted(to: unit)
    }
}
