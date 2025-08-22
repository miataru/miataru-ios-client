/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DebugLog.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-08-22.
 */

import Foundation

// Conditional debug logger: compiled out in non-Debug builds
#if DEBUG
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    print(message())
}
#else
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {}
#endif


