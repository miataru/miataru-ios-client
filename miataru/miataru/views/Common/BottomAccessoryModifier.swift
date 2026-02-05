/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * BottomAccessoryModifier.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-10-11.
 */

import SwiftUI
import UIKit

struct BottomAccessoryModifier: ViewModifier {
    @EnvironmentObject private var routeInfoState: RouteInfoState
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme

    let onAccessoryTap: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if routeInfoState.isVisible {
                    routeInfoAccessory
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeAreaBottomInset + (routeInfoState.isChromeVisible ? 40 : 12))
                }
            }
    }

    private var routeInfoAccessory: some View {
        let cornerRadius: CGFloat = 18
        return routeInfoBackground(for: cornerRadius)
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 12)
    }

    @ViewBuilder
    private func routeInfoBackground(for cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            routeInfoContent
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
                .overlay(strokeOverlay(cornerRadius: cornerRadius))
        } else {
            routeInfoContent
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(strokeOverlay(cornerRadius: cornerRadius))
        }
    }

    private var routeInfoContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: settings.navigationTransportType == 0 ? "figure.walk" : routeInfoState.transportSymbolName)
                let baseText = "\(routeInfoState.distanceText) • \(routeInfoState.etaText)"
                let mutualSuffix = routeInfoState.isMutualNavigation ? " - \(NSLocalizedString("mutual_navigation_active", comment: "Indicates that both devices are actively navigating to each other"))" : ""
                Text(baseText + mutualSuffix)
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onAccessoryTap?()
            }

            Button(role: .destructive) {
                routeInfoState.onCancel?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text(NSLocalizedString("cancel", comment: "Cancel navigation")))
            }
            .padding(10)
            .contentShape(Rectangle())
            .padding(-10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(.primary)
        .id(colorScheme)
    }

    private func strokeOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(glassStrokeColor, lineWidth: 1)
    }

    private var glassStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.25)
            : Color.white.opacity(0.4)
    }
}

private extension BottomAccessoryModifier {
    var safeAreaBottomInset: CGFloat {
        guard
            let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
        else {
            return 0
        }

        return window.safeAreaInsets.bottom
    }
}

extension View {
    func bottomAccessory(onTap: (() -> Void)? = nil) -> some View {
        modifier(BottomAccessoryModifier(onAccessoryTap: onTap))
    }
}


