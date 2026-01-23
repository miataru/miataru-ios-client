import SwiftUI

struct RouteStyle {
    /// Color for the already traversed portion of the route.
    static var completed: Color = .green
    /// Color for the remaining portion of the route.
    static var remaining: Color = .blue
    /// Color for the default route, when remaining is not displayed
    static var withoutRemaining: Color = .blue
    /// Color for the mutual navigation overlay (when both devices are navigating to each other)
    static var mutualNavigation: Color = .orange
}
