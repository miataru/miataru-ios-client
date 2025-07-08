import SwiftUI

struct OnboardingContainerView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    
    private let iPhone_pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingPermissionsView()),
        AnyView(iPhone_3_OnboardingServerView())
    ]
    private let iPad_pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingPermissionsView()),
        AnyView(iPhone_3_OnboardingServerView())
    ]
    private let macOS_pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingPermissionsView()),
        AnyView(iPhone_3_OnboardingServerView())
    ]
    
    
    var body: some View {
        #if os(macOS)
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
                    Button("Back") { currentPage -= 1 }
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
        #else
        if horizontalSizeClass == .compact {
            // iPhone-spezifische View
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
                        Button("Back") { currentPage -= 1 }
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
        } else {
            // iPad-spezifische View
            VStack {
                TabView(selection: $currentPage) {
                    ForEach(0..<iPad_pages.count, id: \.self) { index in
                        iPad_pages[index]
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                HStack {
                    if currentPage > 0 {
                        Button("Back") { currentPage -= 1 }
                    }
                    Spacer()
                    if currentPage < iPad_pages.count - 1 {
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
        #endif
    }
}

struct OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    static var previews: some View {
        OnboardingContainerView(isPresented: $isPresented)
    }
}

