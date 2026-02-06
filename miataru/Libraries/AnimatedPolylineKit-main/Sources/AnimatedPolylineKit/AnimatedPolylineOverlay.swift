//
//  AnimatedPolylineOverlay.swift
//  AnimatedPolylineKit
//
//  MKOverlay that holds route coordinates, configuration, and progress. The renderer
//  reads progress to know where along the path to draw the moving patch.
//

import MapKit

/// Registry mapping overlay identity to its renderer. Used when progress is set from a
/// background thread: we dispatch to main and call setNeedsDisplay on the renderer by ID
/// without capturing the overlay (avoids Swift 6 sendability and retain cycles).
/// All access to `renderers` is protected by `lock`.
enum AnimatedPolylineOverlayRegistry {
    private final class WeakRef<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
    private static let lock = NSLock()
    private nonisolated(unsafe) static var renderers: [ObjectIdentifier: WeakRef<MKOverlayRenderer>] = [:]

    static func register(overlayID: ObjectIdentifier, renderer: MKOverlayRenderer) {
        lock.lock()
        defer { lock.unlock() }
        renderers[overlayID] = WeakRef(renderer)
    }

    static func unregister(overlayID: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        renderers[overlayID] = nil
    }

    /// Asks the renderer for this overlay to redraw on the next frame. Call from main only.
    static func invalidateRenderer(for overlayID: ObjectIdentifier) {
        lock.lock()
        let ref = renderers[overlayID]
        lock.unlock()
        ref?.value?.setNeedsDisplay()
    }
}

/// MapKit overlay that holds route coordinates, configuration, and animation progress.
/// The renderer uses progress to position the moving patch; the driver (or your code) sets progress over time.
public final class AnimatedPolylineOverlay: NSObject, MKOverlay {
    /// Route coordinates (copy from MKPolyline or your own array).
    public let coordinates: [CLLocationCoordinate2D]
    /// Configuration used by the renderer for colors, patch, and line style.
    public let configuration: AnimatedPolylineConfiguration

    /// Position along the route in [0, 1]. 0 = start, 1 = end. When set, the renderer is invalidated so the map redraws.
    /// Thread-safe: can be set from any thread; invalidation is dispatched to main when needed.
    public var progress: Double {
        get {
            progressLock.lock()
            defer { progressLock.unlock() }
            return _progress
        }
        set {
            let clamped = min(1, max(0, newValue))
            progressLock.lock()
            _progress = clamped
            progressLock.unlock()
            if Thread.isMainThread {
                renderer?.setNeedsDisplay()
            } else {
                // Use registry so we don't capture overlay; main thread will invalidate by overlay ID.
                let overlayID = ObjectIdentifier(self)
                DispatchQueue.main.async {
                    AnimatedPolylineOverlayRegistry.invalidateRenderer(for: overlayID)
                }
            }
        }
    }
    private var _progress: Double = 0
    private let progressLock = NSLock()

    /// Weak reference to the renderer; set by the renderer in its init when it receives this overlay.
    weak var renderer: MKOverlayRenderer?

    /// Required by MKOverlay: a single representative coordinate (we use the first route point).
    public var coordinate: CLLocationCoordinate2D {
        guard let first = coordinates.first else {
            return kCLLocationCoordinate2DInvalid
        }
        return first
    }

    /// Required by MKOverlay: the map rect that contains all route points (used for culling and placement).
    public var boundingMapRect: MKMapRect {
        guard !coordinates.isEmpty else {
            return .null
        }
        var rect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            if rect.isNull {
                rect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            } else {
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        }
        return rect
    }

    /// Creates an overlay from an array of coordinates (e.g. from your own route source).
    public init(coordinates: [CLLocationCoordinate2D], configuration: AnimatedPolylineConfiguration) {
        self.coordinates = coordinates
        self.configuration = configuration
        super.init()
    }

    /// Creates an overlay by copying coordinates from an existing MKPolyline (e.g. from MKDirections).
    public convenience init(polyline: MKPolyline, configuration: AnimatedPolylineConfiguration) {
        var coords: [CLLocationCoordinate2D] = []
        let pointCount = polyline.pointCount
        if pointCount > 0 {
            let points = polyline.points()
            coords = (0..<pointCount).map { points[$0].coordinate }
        }
        self.init(coordinates: coords, configuration: configuration)
    }
}
