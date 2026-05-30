/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DebugLog.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-08-22.
 */
import Foundation
import os

#if DEBUG
private let debugLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.miataru.ios",
    category: "Debug"
)

@inline(__always)
func debugLog(_ message: String) {
    debugLogger.debug("\(message, privacy: .public)")
}
#else
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {}
#endif
