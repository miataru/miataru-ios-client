import Foundation

enum LocaleSwitcher {
    static func setAppleLanguages(_ codes: [String]) {
        UserDefaults.standard.set(codes, forKey: "AppleLanguages")
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        UserDefaults.standard.synchronize()
    }

    static func waitForPropagation() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    static func normalizedIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
