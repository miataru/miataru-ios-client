/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * RouteInfoState.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-10-11.
 */

import Foundation
import SwiftUI

final class RouteInfoState: ObservableObject {
    static let shared = RouteInfoState()

    @Published var isVisible: Bool = false
    @Published var etaText: String = ""
    @Published var distanceText: String = ""
    @Published var transportSymbolName: String = "car"

    // Optional handler to cancel the current navigation/session
    var onCancel: (() -> Void)?

    func update(etaText: String?, distanceText: String?, transportSymbolName: String?, visible: Bool) {
        self.etaText = etaText ?? ""
        self.distanceText = distanceText ?? ""
        self.transportSymbolName = transportSymbolName ?? self.transportSymbolName
        self.isVisible = visible && ((etaText?.isEmpty == false) || (distanceText?.isEmpty == false))
    }

    func hide() {
        isVisible = false
        etaText = ""
        distanceText = ""
    }
}


