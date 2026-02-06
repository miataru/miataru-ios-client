//
//  AnimatedPolylineKit.swift
//  AnimatedPolylineKit
//
//  Public API for rendering an animated gradient polyline on MKMapView.
//  Flow: App creates AnimatedPolylineConfiguration and AnimatedPolylineOverlay,
//  adds the overlay to the map and provides AnimatedPolylineRenderer in rendererFor.
//  AnimatedPolylineAnimationDriver (or your own code) drives overlay.progress
//  from 0 to 1; the renderer reads progress and draws the moving patch.
//

import MapKit
import SwiftUI

// Types are defined in their respective files and are part of the module.
// Key types:
// - AnimatedPolylineConfiguration  — all colors, patch, duration, easing, line style (app-supplied)
// - AnimatedPolylineDirection / AnimatedPolylineEasing / AnimatedPolylineLineCap / AnimatedPolylineLineJoin
// - AnimatedPolylineOverlay         — holds coordinates, config, and progress; MKOverlay
// - AnimatedPolylineRenderer        — draws full route + moving patch; reads overlay.progress
// - AnimatedPolylineAnimationDriver — turns time into progress [0,1], publish to overlay.progress
// - AnimatedPolylineEasingHelper    — apply easing when driving progress manually
