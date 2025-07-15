// This SwiftUI view acts as a container for onboarding screens.
// It selects the appropriate onboarding view depending on the platform and device size.
import SwiftUI

struct OnboardingContainerView: View {
    // Access the horizontal size class from the environment to distinguish between compact (iPhone) and regular (iPad) layouts
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    // Binding to control whether the onboarding is presented
    @Binding var isPresented: Bool
    // Tracks the current page in the onboarding flow
    @State private var currentPage = 0
    
    var body: some View {
        #if os(macOS)
        // Use the macOS-specific onboarding container view
        MacOnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
        #else
        if horizontalSizeClass == .compact {
            // Show the iPhone-specific onboarding container view for compact width devices
            iPhone_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
        } else {
            // Show the iPad-specific onboarding container view for regular width devices
            iPad_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
        }
        #endif
    }
}

// Preview provider for SwiftUI previews
struct OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    static var previews: some View {
        OnboardingContainerView(isPresented: $isPresented)
    }
}

