import SwiftUI

struct Mac_OnboardingContainerView: View {
    @Binding var isPresented: Bool
    @Binding var currentPage: Int
    
    private let macOS_pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingLocationPermissionView()),
        AnyView(iPhone_2b_OnboardingCameraPermissionView()),
        AnyView(iPhone_3_OnboardingServerView())
    ]
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<macOS_pages.count, id: \.self) { index in
                    macOS_pages[index]
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            HStack {
                if currentPage > 0 {
                    Button("Previous") { currentPage -= 1 }
                }
                Spacer()
                if currentPage < macOS_pages.count - 1 {
                    Button("Next") { currentPage += 1 }
                } else {
                    Button("Finish") {
                        UserDefaults.standard.hasCompletedOnboarding = true
                        isPresented = false
                    }
                }
            }
            .padding()
        }
    }
} 
