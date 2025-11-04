/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceHistoryCacheStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import Combine
import MiataruAPIClient

class DeviceHistoryCacheStore: ObservableObject {
    static let shared = DeviceHistoryCacheStore()
    @Published private var histories: [String: [MiataruLocationData]] = [:]
    private init() {}

    func setHistory(_ history: [MiataruLocationData], for deviceID: String) {
        histories[deviceID] = history
    }

    func getHistory(for deviceID: String) -> [MiataruLocationData]? {
        histories[deviceID]
    }
}
