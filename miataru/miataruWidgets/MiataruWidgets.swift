/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruWidgets.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import WidgetKit
import SwiftUI

@main
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct MiataruWidgets: WidgetBundle {
    var body: some Widget {
        DeviceLocationTextWidget()
        DeviceLocationMapWidget()
    }
}

