/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceNameLabel.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI
@preconcurrency import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Shared in-memory cache for rasterized device name labels
final class DeviceNameLabelImageCache {
    static let shared = DeviceNameLabelImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    private init() {
        cache.countLimit = 256
    }
    func image(for key: String) -> PlatformImage? {
        let image = cache.object(forKey: key as NSString)
        if image != nil {
            debugLog("DeviceNameLabel cache HIT for key: \(key)")
        } else {
            debugLog("DeviceNameLabel cache MISS for key: \(key)")
        }
        return image
    }
    func set(_ image: PlatformImage, for key: String, cost: Int = 0) {
        debugLog("DeviceNameLabel cache STORE for key: \(key), cost: \(cost)")
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

struct DeviceNameLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let deviceName: String
    let deviceID: String
    let font: Font
    let topPadding: CGFloat
    let opacity: Double
    let cacheEnabled: Bool
    
    @State private var cachedImage: PlatformImage?
    @State private var cachedImageKey: String?
    
    init(deviceName: String, deviceID: String, font: Font = .callout, topPadding: CGFloat = 2, opacity: Double = 1.0, cacheEnabled: Bool = true) {
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.font = font
        self.topPadding = topPadding
        self.opacity = opacity
        self.cacheEnabled = cacheEnabled
    }
    
    private var displayText: String {
        deviceName.isEmpty ? deviceID : deviceName
    }
    
    private var cacheKey: String {
        [
            displayText,
            String(describing: font),
            String(format: "%.2f", topPadding),
            String(format: "%.3f", opacity),
            String(describing: colorScheme),
            String(describing: sizeCategory),
            String(describing: dynamicTypeSize),
            String(format: "%.2f", displayScale)
        ].joined(separator: "|")
    }

    private var rawLabel: some View {
        ZStack {
            ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                    if x != 0 || y != 0 {
                        Text(displayText)
                            .font(font)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .padding(.top, topPadding)
                            .offset(x: CGFloat(x), y: CGFloat(y))
                    }
                }
            }
            Text(displayText)
                .font(font)
                .foregroundColor(Color(UIColor.label).opacity(opacity))
                .padding(.top, topPadding)
        }
    }

    var body: some View {
        Group {
            if cacheEnabled {
                #if canImport(UIKit)
                if let image = (cachedImageKey == cacheKey ? cachedImage : nil) ?? DeviceNameLabelImageCache.shared.image(for: cacheKey) {
                    Image(uiImage: image)
                        .renderingMode(.original)
                        .interpolation(.high)
                } else {
                    rawLabel
                        .task(id: cacheKey) {
                            guard DeviceNameLabelImageCache.shared.image(for: cacheKey) == nil else { 
                                debugLog("DeviceNameLabel task skipped - image already cached for key: \(cacheKey)")
                                return 
                            }
                            debugLog("DeviceNameLabel RENDERING new image for key: \(cacheKey)")
                            let content = rawLabel
                                .environment(\.colorScheme, colorScheme)
                                .environment(\.sizeCategory, sizeCategory)
                                .environment(\.dynamicTypeSize, dynamicTypeSize)
                            let renderer = ImageRenderer(content: content)
                            renderer.scale = displayScale
                            renderer.isOpaque = false
                            if let uiImage = renderer.uiImage {
                                let outputImage = uiImage.withRenderingMode(.alwaysOriginal)
                                let cost = (uiImage.pngData()?.count) ?? 0
                                DeviceNameLabelImageCache.shared.set(outputImage, for: cacheKey, cost: cost)
                                cachedImage = outputImage
                                cachedImageKey = cacheKey
                            }
                        }
                }
                #elseif canImport(AppKit)
                if let image = (cachedImageKey == cacheKey ? cachedImage : nil) ?? DeviceNameLabelImageCache.shared.image(for: cacheKey) {
                    Image(nsImage: image)
                        .renderingMode(.original)
                        .interpolation(.high)
                } else {
                    rawLabel
                        .task(id: cacheKey) {
                            guard DeviceNameLabelImageCache.shared.image(for: cacheKey) == nil else { 
                                debugLog("DeviceNameLabel task skipped - image already cached for key: \(cacheKey)")
                                return 
                            }
                            debugLog("DeviceNameLabel RENDERING new image for key: \(cacheKey)")
                            let content = rawLabel
                                .environment(\.colorScheme, colorScheme)
                                .environment(\.sizeCategory, sizeCategory)
                                .environment(\.dynamicTypeSize, dynamicTypeSize)
                            let renderer = ImageRenderer(content: content)
                            renderer.scale = displayScale
                            renderer.isOpaque = false
                            if let nsImage = renderer.nsImage {
                                nsImage.isTemplate = false
                                DeviceNameLabelImageCache.shared.set(nsImage, for: cacheKey)
                                cachedImage = nsImage
                                cachedImageKey = cacheKey
                            }
                        }
                }
                #endif
            } else {
                rawLabel
            }
        }
        .onChange(of: colorScheme) { _, _ in
            // Invalidate local cached image when the appearance changes
            cachedImage = nil
            cachedImageKey = nil
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            // Invalidate local cached image when dynamic type changes
            cachedImage = nil
            cachedImageKey = nil
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DeviceNameLabel(deviceName: "iPhone 15 Pro", deviceID: "device123")
        
        DeviceNameLabel(deviceName: "", deviceID: "device456")
        
        DeviceNameLabel(deviceName: "iPad Air", deviceID: "device789", font: .caption2, topPadding: 1, opacity: 0.8)
    }
    .padding()
    .background(Color.blue.opacity(0.3))
}
