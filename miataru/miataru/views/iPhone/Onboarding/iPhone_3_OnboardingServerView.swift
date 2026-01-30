/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_3_OnboardingServerView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import Combine

struct iPhone_3_OnboardingServerView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.animationsAllowed) private var animationsAllowed
    @State private var useDefaultServer: Bool = true
    @State private var customServerURL: String = ""
    @State private var showURLError: Bool = false
    @FocusState private var customServerFieldIsFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    
    private let defaultServer = "https://service.miataru.com"
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer()
                    Text("Choose the server you trust.")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if keyboardHeight == 0 {
                        Image("selectserver")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .padding(.horizontal)
                    }
                    Text("Your location data is stored on a server you trust. You can use the default Miataru server, or enter your own server address.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Link("Documentation to setup your own server (GitHub)", destination: URL(string: "https://github.com/miataru/miataru-server")!)
                        .font(.footnote)
                        .foregroundStyle(.link)
                        .padding(.bottom, 8)

                    Picker("Server", selection: $useDefaultServer) {
                        Text("Use Default Server").tag(true)
                        Text("Enter Custom Server").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .onChange(of: useDefaultServer) {
                        if !useDefaultServer {
                            customServerFieldIsFocused = true
                        } else {
                            settings.miataruServerURL = defaultServer
                            customServerURL = defaultServer
                        }
                    }
                    VStack(alignment: .leading, spacing: 32) {
                        HStack {
                            TextField("Custom server URL (must start with https://)", text: $customServerURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(.horizontal)
                                .disabled(useDefaultServer)
                                .focused($customServerFieldIsFocused)
                                .onSubmit {
                                    if isValidHTTPSURL(customServerURL) {
                                        settings.miataruServerURL = customServerURL
                                        showURLError = false
                                    } else {
                                        showURLError = true
                                    }
                                }
                            if !useDefaultServer {
                                Button(action: {
                                    if isValidHTTPSURL(customServerURL) {
                                        settings.miataruServerURL = customServerURL
                                        showURLError = false
                                        customServerFieldIsFocused = false
                                    } else {
                                        showURLError = true
                                    }
                                }) {
                                    Image(systemName: isValidHTTPSURL(customServerURL) ? "checkmark.circle.fill" : "checkmark.circle")
                                        .foregroundColor(isValidHTTPSURL(customServerURL) ? .accentColor : .secondary)
                                }
                                .disabled(!isValidHTTPSURL(customServerURL))
                                .padding(.trailing, 12)
                            }
                        }
                        if showURLError && !useDefaultServer {
                            Text("Please enter a valid https server URL.")
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                    Text("").padding(.bottom,16)

                    Spacer()
                }
                .frame(minHeight: geometry.size.height - keyboardHeight)
            }
        }
        .animation(animationsAllowed ? .easeOut(duration: 0.25) : nil, value: keyboardHeight)
        .padding()
        .background(Color(.systemBackground))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onAppear {
            if settings.miataruServerURL != defaultServer {
                useDefaultServer = false
                customServerURL = settings.miataruServerURL
            } else {
                useDefaultServer = true
                customServerURL = ""
            }
        }
        .onDisappear {
            if !useDefaultServer && isValidHTTPSURL(customServerURL) {
                settings.miataruServerURL = customServerURL
            }
        }
    }
    
    private func isValidHTTPSURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://") else { return false }
        guard let u = URL(string: trimmed), u.scheme == "https" else { return false }
        guard !trimmed.contains(" ") else { return false }
        // Es muss mindestens ein Punkt nach https:// folgen (Domain-Prüfung)
        let host = u.host ?? ""
        guard host.contains(".") else { return false }
        return true
    }
}

#Preview {
    iPhone_3_OnboardingServerView()
} 
