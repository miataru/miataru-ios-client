/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryPanelRestorePill.swift
 * miataru
 */

import SwiftUI

struct HistoryPanelRestorePill: View {
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.up")
                .imageScale(.small)
            Text(NSLocalizedString("history_panel_restore", comment: "Button title to restore the hidden history panel"))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(historyRestoreBackground)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onRestore)
        .accessibilityLabel(Text(NSLocalizedString("history_panel_restore_accessibility", comment: "Accessibility label to restore the hidden history panel")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(NSLocalizedString("history_panel_restore_accessibility", comment: "Accessibility label to restore the hidden history panel"))) {
            onRestore()
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    guard value.translation.height < -30 else { return }
                    onRestore()
                }
        )
    }

    @ViewBuilder
    private var historyRestoreBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.clear)
                .glassEffect(in: .capsule)
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
