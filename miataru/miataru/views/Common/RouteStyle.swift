import SwiftUI

struct RouteStyle {
    /// Color for the already traversed portion of the route.
    static var completed: Color = .blue
    /// Color for the remaining portion of the route.
    static var remaining: Color = .gray.opacity(0.4)
}
