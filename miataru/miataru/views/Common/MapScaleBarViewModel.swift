/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MapScaleBarViewModel.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-09-07.
 */

import Foundation
import SwiftUI
import MapKit

final class MapScaleBarViewModel: ObservableObject {
    @Published private(set) var label: String = ""

    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.12

    private var lastRegion: MKCoordinateRegion?
    private var lastWidth: CGFloat?

    // Change thresholds to avoid thrashing updates for tiny movements/zooms
    private let relativeSpanThreshold: Double = 0.02 // 2% delta in longitudeDelta
    private let latitudeChangeThreshold: CLLocationDegrees = 0.25 // quarter of a degree change
    private let widthChangeThreshold: CGFloat = 0.5 // half a point change

    private struct CacheKey: Hashable {
        let spanBucket: Int
        let centerLatBucket: Int
        let widthBucket: Int
        let isMetric: Bool
    }

    private var lastCacheKey: CacheKey?

    func schedule(region: MKCoordinateRegion, width: CGFloat) {
        // Early exit if changes are negligible
        if let previousRegion = lastRegion, let previousWidth = lastWidth {
            let previousSpan = previousRegion.span.longitudeDelta
            let currentSpan = region.span.longitudeDelta
            let spanRelativeChange = abs(currentSpan - previousSpan) / max(previousSpan, .leastNonzeroMagnitude)
            let latitudeChange = abs(region.center.latitude - previousRegion.center.latitude)
            let widthChange = abs(width - previousWidth)
            if spanRelativeChange < relativeSpanThreshold && latitudeChange < latitudeChangeThreshold && widthChange < widthChangeThreshold {
                return
            }
        }

        lastRegion = region
        lastWidth = width

        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.compute(region: region, width: width)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func compute(region: MKCoordinateRegion, width: CGFloat) {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }

        // Bucket inputs to reduce recomputations and re-renders from tiny changes
        let spanBucket = Self.bucketSpan(region.span.longitudeDelta)
        let centerLatBucket = Self.bucketLatitude(region.center.latitude)
        let widthBucket = Self.bucketWidth(width)
        let key = CacheKey(spanBucket: spanBucket, centerLatBucket: centerLatBucket, widthBucket: widthBucket, isMetric: usesMetric)

        if key == lastCacheKey {
            return // Nothing significant changed
        }

        // Compute the raw distance for the given width
        let distance = Self.distanceForWidth(region: region, width: width)
        let label = Self.distanceLabel(for: distance)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastCacheKey = key
            self.label = label
        }
    }

    // MARK: - Helpers

    private static func bucketSpan(_ span: CLLocationDegrees) -> Int {
        // Log-scale bucket to keep the same bucket across tiny changes; 2 decimals in log10 space
        let clamped = max(span, .leastNonzeroMagnitude)
        let logScaled = log10(clamped)
        return Int((logScaled * 100.0).rounded())
    }

    private static func bucketLatitude(_ latitude: CLLocationDegrees) -> Int {
        // Bucket by 1 degree; distance per longitude varies with cos(latitude)
        return Int(latitude.rounded())
    }

    private static func bucketWidth(_ width: CGFloat) -> Int {
        // Pixel-level bucket
        return Int(width.rounded())
    }

    private static func distanceForWidth(region: MKCoordinateRegion, width: CGFloat) -> CLLocationDistance {
        // Calculate the distance that 'width' points cover on the map
        let mapViewWidth = UIScreen.main.bounds.width
        let span = region.span
        let center = region.center
        let loc1 = CLLocation(latitude: center.latitude, longitude: center.longitude - span.longitudeDelta / 2 * Double(width / mapViewWidth))
        let loc2 = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta / 2 * Double(width / mapViewWidth))
        return loc1.distance(from: loc2)
    }

    private static func distanceLabel(for distance: CLLocationDistance) -> String {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        if usesMetric {
            if distance > 1000 {
                // Localized: Kilometer unit for scale bar
                let format = NSLocalizedString("scalebar_kilometers", comment: "Scale bar: display distance in kilometers")
                return String(format: format, distance / 1000)
            } else {
                // Localized: Meter unit for scale bar
                let format = NSLocalizedString("scalebar_meters", comment: "Scale bar: display distance in meters")
                return String(format: format, distance)
            }
        } else {
            // Imperial: miles and feet
            let distanceInFeet = distance / 0.3048
            let distanceInMiles = distance / 1609.34
            if distanceInFeet > 528 { // More than 1/10 mile
                // Localized: Miles unit for scale bar
                let format = NSLocalizedString("scalebar_miles", comment: "Scale bar: display distance in miles")
                return String(format: format, distanceInMiles)
            } else {
                // Localized: Feet unit for scale bar
                let format = NSLocalizedString("scalebar_feet", comment: "Scale bar: display distance in feet")
                return String(format: format, distanceInFeet)
            }
        }
    }
}


