/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * AppNavigationCoordinator.swift
 * miataru
 *
 * Created by Codex on 26.04.26.
 */

import Combine
import Foundation

enum AppRootNavigationDestination: Equatable {
    case settings
}

enum SettingsNavigationDestination: Equatable {
    case advancedOptions
}

struct SettingsNavigationRequest: Equatable, Identifiable {
    let id = UUID()
    let destination: SettingsNavigationDestination
}

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let shared = AppNavigationCoordinator()

    @Published private(set) var rootDestination: AppRootNavigationDestination?
    @Published private(set) var settingsRequest: SettingsNavigationRequest?

    private init() {}

    func openAdvancedSettings() {
        rootDestination = .settings
        settingsRequest = SettingsNavigationRequest(destination: .advancedOptions)
    }

    func consumeSettingsRequest(_ request: SettingsNavigationRequest) {
        guard settingsRequest?.id == request.id else { return }
        settingsRequest = nil
        rootDestination = nil
    }
}
