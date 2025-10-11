/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * BottomAccessoryModifier.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-10-11.
 */

import SwiftUI

struct BottomAccessoryModifier: ViewModifier {
    @EnvironmentObject private var routeInfoState: RouteInfoState
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.colorScheme) private var colorScheme
    let onAccessoryTap: (() -> Void)?

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .tabViewBottomAccessory {
                        if routeInfoState.isVisible {
                            HStack {
                                // Left tappable region (excludes the cancel button)
                                HStack {
                                    Image(systemName: settings.navigationTransportType == 0 ? "figure.walk" : routeInfoState.transportSymbolName)
                                    Text("\(routeInfoState.distanceText) • \(routeInfoState.etaText)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onAccessoryTap?()
                                }

                                // Cancel button (non-propagating)
                                Button(role: .destructive) {
                                    routeInfoState.onCancel?()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.red)
                                        .accessibilityLabel(Text(NSLocalizedString("cancel", comment: "Cancel navigation")))
                                }
                                // Expand hit area to ~44x44 without changing layout
                                .padding(10)
                                .contentShape(Rectangle())
                                .padding(-10)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundColor(.primary)
                            .id(colorScheme)
                        } else {
                            EmptyView()
                        }
                    }
            } else {
                content
            }
        }
    }
}

extension View {
    func bottomAccessory(onTap: (() -> Void)? = nil) -> some View {
        modifier(BottomAccessoryModifier(onAccessoryTap: onTap))
    }
}


