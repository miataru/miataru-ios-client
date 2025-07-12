import SwiftUI

struct iPhone_OnboardingContainerView: View {
    @Binding var isPresented: Bool
    @Binding var currentPage: Int
    
    private let iPhone_pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingLocationPermissionView()),
        AnyView(iPhone_2b_OnboardingCameraPermissionView()),
        AnyView(iPhone_3_OnboardingServerView()),
        AnyView(iPhone_4_OnboardingLocationHistoryView())
    ]
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<iPhone_pages.count, id: \.self) { index in
                    iPhone_pages[index]
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
                if currentPage < iPhone_pages.count - 1 {
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
