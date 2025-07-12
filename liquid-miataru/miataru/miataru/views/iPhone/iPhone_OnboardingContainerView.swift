import SwiftUI

struct iPhone_OnboardingContainerView: View {
    @Binding var isPresented: Bool
    @Binding var currentPage: Int
    
    private let pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingLocationPermissionView()),
        AnyView(iPhone_3_OnboardingServerView()),
        AnyView(iPhone_4_OnboardingLocationHistoryView()),
        AnyView(iPhone_5_OnboardingQRcodeView()),
        AnyView(iPhone_6_OnboardingDoneView())
    ]
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    pages[index]
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
                if currentPage < pages.count - 1 {
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

struct iPhone_OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    @State static var currentPage = 0
    static var previews: some View {
        iPhone_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
    }
}
