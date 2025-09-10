/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruMapMarker.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Hilfs-Extension für Kontrastbestimmung
extension Color {
    /// Returns true if the color is considered 'light' (für Kontrast)
    func isLight(threshold: Float = 0.6) -> Bool {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return Float(luminance) > threshold
#else
        return false // macOS: ggf. NSColor analog
#endif
    }
}

// Zusatz-Utilities für Cache-Key und Bild-Cache
extension Color {
    /// Stabile RGBA-Repräsentation für Cache-Keys
    func rgbaKey() -> String {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "r%.3fg%.3fb%.3fa%.3f", r, g, b, a)
#elseif canImport(AppKit)
        return String(describing: self)
#else
        return String(describing: self)
#endif
    }
}

final class MiataruMapMarkerImageCache {
    static let shared = MiataruMapMarkerImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    private init() {
        cache.countLimit = 256
    }
    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }
    func set(_ image: PlatformImage, for key: String, cost: Int = 0) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

struct MiataruMapMarker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var color: Color = .red
    var iconName: String = "mappin"
    var height: CGFloat = 40
    var cacheEnabled: Bool = true
    /// Extra padding used only for prerendering to avoid clipping shadows
    var renderPadding: CGFloat = 8

    @State private var cachedImage: PlatformImage?
    @State private var cachedImageKey: String?

    private var cacheKey: String {
        [
            color.rgbaKey(),
            iconName,
            String(format: "h%.2f", height),
            String(describing: colorScheme),
            String(format: "s%.2f", displayScale),
            String(format: "p%.1f", renderPadding)
        ].joined(separator: "|")
    }

    // Statischer Marker (ohne Pulsing)
    private var staticMarker: some View {
        let circleDiameter = height * 0.65
        let triangleHeight = height * 0.45
        let triangleWidth = circleDiameter * 0.54
        let iconSize = circleDiameter * 0.54
        let totalWidth = max(circleDiameter, triangleWidth) + 4

        return ZStack {
            Triangle()
                .fill(color.opacity(0.9))
                .background(
                    Triangle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Triangle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    (color.isLight() ? Color.black : Color.white).opacity(0.7),
                                    (color.isLight() ? Color.black : Color.white).opacity(0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                .frame(width: triangleWidth, height: triangleHeight)
                .offset(y: circleDiameter/2 - triangleHeight/2 + 6)
                .shadow(radius: 1, y: 1)

            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(1),
                            color.opacity(0.4)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    (color.isLight() ? Color.black : Color.white).opacity(0.7),
                                    (color.isLight() ? Color.black : Color.white).opacity(0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.18),
                                    Color.clear
                                ]),
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: circleDiameter * 0.7
                            )
                        )
                )
                .frame(width: circleDiameter, height: circleDiameter)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                .overlay(
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(color.isLight() ? .black : .white)
                )
        }
        .frame(width: totalWidth, height: height)
    }

    var body: some View {
        let markerFineTuneYOffset: CGFloat = 0

        ZStack {
            Group {
                if cacheEnabled {
#if canImport(UIKit)
                    if let image = (cachedImageKey == cacheKey ? cachedImage : nil) ?? MiataruMapMarkerImageCache.shared.image(for: cacheKey) {
                        Image(uiImage: image)
                    } else {
                        staticMarker
                            .task(id: cacheKey) {
                                guard MiataruMapMarkerImageCache.shared.image(for: cacheKey) == nil else { return }
                                let content = staticMarker
                                    .environment(\.colorScheme, colorScheme)
                                let renderer = ImageRenderer(content: content)
                                renderer.scale = displayScale
                                renderer.isOpaque = false
                                if let uiImage = renderer.uiImage {
                                    let cost = (uiImage.pngData()?.count) ?? 0
                                    MiataruMapMarkerImageCache.shared.set(uiImage, for: cacheKey, cost: cost)
                                    cachedImage = uiImage
                                    cachedImageKey = cacheKey
                                }
                            }
                    }
#elseif canImport(AppKit)
                    if let image = (cachedImageKey == cacheKey ? cachedImage : nil) ?? MiataruMapMarkerImageCache.shared.image(for: cacheKey) {
                        Image(nsImage: image)
                    } else {
                        staticMarker
                            .task(id: cacheKey) {
                                guard MiataruMapMarkerImageCache.shared.image(for: cacheKey) == nil else { return }
                                let content = staticMarker
                                    .environment(\.colorScheme, colorScheme)
                                let renderer = ImageRenderer(content: content)
                                renderer.scale = displayScale
                                renderer.isOpaque = false
                                if let nsImage = renderer.nsImage {
                                    MiataruMapMarkerImageCache.shared.set(nsImage, for: cacheKey)
                                    cachedImage = nsImage
                                    cachedImageKey = cacheKey
                                }
                            }
                    }
#endif
                } else {
                    staticMarker
                        .padding(EdgeInsets(top: renderPadding, leading: renderPadding, bottom: 0, trailing: renderPadding))
                }
            }
        }
        .offset(y: markerFineTuneYOffset)
        .onChange(of: colorScheme) { _, _ in
            // Invalidate local cached image when the appearance changes
            cachedImage = nil
            cachedImageKey = nil
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        MiataruMapMarker(color: .red, height: 40)
        MiataruMapMarker(color: .blue, iconName: "car", height: 60)
        MiataruMapMarker(color: .green, iconName: "bicycle", height: 30)
        MiataruMapMarker(color: .orange, iconName: "star", height: 80)
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
