/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_VisitorHistoryView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-19.
 */

import SwiftUI
import MiataruAPIClient

struct iPhone_VisitorHistoryView: View {
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var visitors: [MiataruVisitor] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(NSLocalizedString("visitor_history_retry", comment: "Button to retry loading visitor history")) {
                        loadVisitorHistory()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if visitors.isEmpty {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("visitor_history_empty", comment: "Empty state message when no visitors have accessed the device"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(sortedVisitors, id: \.DeviceID) { visitor in
                    VisitorHistoryRow(
                        visitor: visitor,
                        knownDevice: deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() },
                        onAddDevice: {
                            pendingDeviceID = visitor.DeviceID
                            showAddDeviceSheet = true
                        }
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("visitor_history_title", comment: "Title for visitor history screen"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadVisitorHistory()
        }
        .sheet(isPresented: $showAddDeviceSheet, onDismiss: {
            pendingDeviceID = nil
            // Refresh visitor history after adding device to show updated name
            loadVisitorHistory()
        }) {
            if let deviceID = pendingDeviceID {
                iPhone_AddDeviceView(
                    store: deviceStore,
                    isPresented: $showAddDeviceSheet,
                    prefillDeviceID: deviceID
                )
            }
        }
        .onReceive(deviceStore.$devices) { _ in
            // Refresh when devices are added/updated to show updated names
            if !visitors.isEmpty {
                // Trigger view update by accessing sortedVisitors
                _ = sortedVisitors
            }
        }
    }
    
    private var sortedVisitors: [MiataruVisitor] {
        visitors.sorted { $0.TimeStampDate > $1.TimeStampDate }
    }
    
    private func loadVisitorHistory() {
        guard let url = URL(string: settings.miataruServerURL) else {
            errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let ourDeviceId = thisDeviceIDManager.shared.deviceID
                let fetchedVisitors = try await MiataruAPIClient.getVisitorHistory(
                    serverURL: url,
                    forDeviceID: ourDeviceId,
                    amount: 100
                )
                
                await MainActor.run {
                    self.visitors = fetchedVisitors
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
                    self.isLoading = false
                }
                debugLog("[iPhone_VisitorHistoryView] Failed to load visitor history: \(error)")
            }
        }
    }
}

struct VisitorHistoryRow: View {
    let visitor: MiataruVisitor
    let knownDevice: KnownDevice?
    let onAddDevice: () -> Void
    
    @State private var now = Date()
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let device = knownDevice {
                    Text(device.DeviceName)
                        .font(.headline)
                } else {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("unknown_device_label", comment: "Label for unknown/unrecognized device"))
                            .font(.headline)
                        Text(shortenedDeviceID(visitor.DeviceID))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                Text(formatRelativeTime(visitor.TimeStampDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if knownDevice == nil {
                Button(action: onAddDevice) {
                    Text(NSLocalizedString("add_device_action", comment: "Button label to add an unknown device"))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(NSLocalizedString("add_device_action", comment: "Button label to add an unknown device"))
                .accessibilityHint(NSLocalizedString("add_device_accessibility_hint", comment: "Accessibility hint for add device button"))
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
    }
    
    private func shortenedDeviceID(_ deviceID: String) -> String {
        guard deviceID.count > 10 else { return deviceID }
        let start = String(deviceID.prefix(6))
        let end = String(deviceID.suffix(4))
        return "\(start)...\(end)"
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return NSLocalizedString("time_just_now", comment: "Indicates very recent time, within the last minute")
        } else if diff < 3600 {
            let minutes = Int(diff / 60)
            return String(format: NSLocalizedString("time_ago_minutes", comment: "Time ago format for minutes, e.g., '5 min ago'"), minutes)
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return String(format: NSLocalizedString("time_ago_hours", comment: "Time ago format for hours, e.g., '2 hr ago'"), hours)
        } else {
            let days = Int(diff / 86400)
            return String(format: NSLocalizedString("time_ago_days", comment: "Time ago format for days, e.g., '3 days ago'"), days)
        }
    }
}
