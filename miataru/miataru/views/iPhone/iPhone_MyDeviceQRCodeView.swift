/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_MyDeviceQRCodeView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import QRCode
import MessageUI
import UIKit
import MiataruAPIClient

struct iPhone_MyDeviceQRCodeView: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    @State var content: String = DeviceLinkResolver.urlString(for: thisDeviceIDManager.shared.deviceID)
    @State private var currentDeviceID = thisDeviceIDManager.shared.deviceID
    @State var correction: QRCode.ErrorCorrection = .low

    @State var dataColor: Color = .primary
    @State var eyeColor: Color = .primary
    @State var pupilColor: Color = .primary
    @State var backgroundColor: Color = .clear

    @State var pixelShape: String = "square"
    @State var eyeStyle: String = "square"
    @State var pupilStyle: String = "square"

    @State var dataInset: Double = 0
    @State var cornerRadiusFraction: Double = 0.5
    @State var rotationFraction: Double = 0.0

    @State private var showCopiedAlert = false
    @State private var showMailComposer = false
    @State private var showShareFallback = false
    @State private var showDeviceKeySheet = false
    @State private var showTrackingPauseSheet = false
    @State private var qrImage: UIImage? = nil
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @StateObject private var deviceSloganCacheStore = DeviceSloganCacheStore.shared
    @StateObject private var visitorHistoryViewModel = VisitorHistoryViewModel()
    @State private var pendingDeviceItem: DeviceIDItem? = nil
    @State private var isVisible: Bool = false
    @State private var showSloganEditor = false
    @State private var ownDeviceSlogan = ""
    @State private var sloganDraft = ""
    @State private var isLoadingSlogan = false
    @State private var isSavingSlogan = false
    @State private var sloganErrorMessage: String? = nil

    private let maxSloganLength = MiataruAppAPI.maxDeviceSloganLength

    let gradient = Gradient(colors: [.black, .pink])
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            NavigationStack {
                ScrollView {
                    qrScrollContent(geometry: geometry, isLandscape: isLandscape)
                .frame(
                    maxWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: isLandscape ? .center : .top
                )
                }
                .accessibilityIdentifier("qr_scroll_content")
                .refreshable {
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: true, force: true)
                }
                .onAppear {
                    isVisible = true
                    _ = synchronizeCurrentDeviceIdentity()
                    hydrateSloganFromCache()
                    Task {
                        await visitorHistoryViewModel.refreshIfNeeded(
                            isVisible: true,
                            force: true,
                            showLoading: visitorHistoryViewModel.visitors.isEmpty
                        )
                        await loadOwnDeviceSloganIfNeeded()
                    }
                }
                .onDisappear {
                    isVisible = false
                }
                .onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate)) { _ in
                    Task {
                        await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task {
                        _ = synchronizeCurrentDeviceIdentity()
                        await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
                        await loadOwnDeviceSloganIfNeeded()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .thisDeviceIDDidChange)) { _ in
                    Task { @MainActor in
                        let didChange = synchronizeCurrentDeviceIdentity()
                        if didChange {
                            hydrateSloganFromCache()
                            await loadOwnDeviceSloganIfNeeded(forceRefresh: true)
                        }
                    }
                }
                .task(id: "\(settings.outsideMapUpdateInterval)-\(settings.autoRefreshDeviceList)") {
                    let seconds = max(5.0, Double(settings.outsideMapUpdateInterval))
                    let interval = UInt64(seconds * 1_000_000_000)
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: interval)
                        guard isVisible,
                              UIApplication.shared.applicationState == .active else { continue }
                        await visitorHistoryViewModel.refreshIfNeeded(isVisible: true)
                    }
                }
                .navigationTitle(String(localized: "my_device", table: "Devices"))
                .navigationBarTitleDisplayMode(isLandscape ? .inline : .large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            showDeviceKeySheet = true
                        }) {
                            Image(systemName: "key.card")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .accessibilityLabel(Text("device_key_button_label", tableName: "Devices"))
                        .accessibilityHint(Text("device_key_button_hint", tableName: "Devices"))
                        .accessibilityIdentifier("qr_device_key_button")
                    }
                    if settings.trackAndReportLocation {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                showTrackingPauseSheet = true
                            }) {
                                Image(systemName: settings.isTrackingPaused ? "pause.circle.fill" : "timer")
                                    .foregroundColor(settings.isTrackingPaused ? .orange : .blue)
                                    .font(.title2)
                            }
                            .accessibilityLabel(Text("tracking_pause_button_label", tableName: "LocationTracking"))
                            .accessibilityHint(Text("tracking_pause_button_hint", tableName: "LocationTracking"))
                            .accessibilityIdentifier("qr_tracking_pause_button")
                        }
                    }
                }
                .overlay(
                // Overlay für Kopier-Bestätigung
                Group {
                    if showCopiedAlert {
                        VStack {
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                
                                Text("device_id_copied_to_clipboard", tableName: "Devices")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.8))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            Spacer()
                        }
                        .transition(animationsAllowed ? .opacity.combined(with: .scale(scale: 0.8)) : .identity)
                        .zIndex(1)
                    }
                    }
                )
                .sheet(isPresented: $showMailComposer, onDismiss: { qrImage = nil }) {
                    MailView(
                        deviceID: currentDeviceID,
                        qrImage: qrImage ?? (generateQRCodeImage() ?? UIImage())
                    )
                }
                .sheet(isPresented: $showShareFallback) {
                    let items: [Any] = {
                        var arr: [Any] = [shareText]
                        if let img = qrImage ?? generateQRCodeImage() { arr.append(img) }
                        return arr
                    }()
                    ActivityView(activityItems: items)
                }
                .sheet(isPresented: $showDeviceKeySheet) {
                    iPhone_DeviceKeySheetView(showsMismatchWarning: false)
                }
                .sheet(isPresented: $showTrackingPauseSheet) {
                    TrackingPauseSheet()
                }
                .sheet(isPresented: $showSloganEditor) {
                    sloganEditorSheet
                }
                .sheet(item: $pendingDeviceItem) { item in
                    iPhone_AddDeviceView(
                        store: deviceStore,
                        isPresented: Binding(
                            get: { pendingDeviceItem != nil },
                            set: { if !$0 { pendingDeviceItem = nil } }
                        ),
                        prefillDeviceID: item.deviceID,
                        allowsDeviceIDEditing: false
                    )
                    .onDisappear {
                        Task {
                            await visitorHistoryViewModel.loadVisitorHistory(showLoading: false)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func qrScrollContent(geometry: GeometryProxy, isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            // QR Code Section
            VStack(spacing: isLandscape ? 16 : 20) {
                ZStack {
                    backgroundColor
                    qrContent
                        .components(.eyeOuter)
                        .fill(eyeColor)
                    qrContent
                        .components(.eyePupil)
                        .fill(pupilColor)
                    qrContent
                        .components(.onPixels)
                        .fill(dataColor)
                }
                .frame(
                    width: min(geometry.size.width * 0.6, geometry.size.height * 0.4, 300),
                    height: min(geometry.size.width * 0.6, geometry.size.height * 0.4, 300),
                    alignment: .center
                )
                .padding(.horizontal, isLandscape ? 20 : 16)
                .padding(.vertical, isLandscape ? 6 : 8)
                
                Text("qr_code_explanation", tableName: "OnboardingQR")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isLandscape ? 40 : 20)
            }
            .padding(.top, isLandscape ? 12 : 16)

            VStack(spacing: isLandscape ? 10 : 12) {
                Text("Device Slogan", tableName: "Devices")
                    .font(isLandscape ? .subheadline : .headline)
                    .foregroundColor(.secondary)

                Button {
                    sloganDraft = ownDeviceSlogan
                    showSloganEditor = true
                } label: {
                    ZStack(alignment: .trailing) {
                        Text(displayedSloganText)
                            .font(.caption2)
                            .foregroundColor(ownDeviceSlogan.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if isLoadingSlogan || isSavingSlogan {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, isLandscape ? 8 : 10)
                    .frame(maxWidth: isLandscape ? 280 : 300)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(isSavingSlogan)

                if let sloganErrorMessage, !sloganErrorMessage.isEmpty {
                    Text(sloganErrorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, isLandscape ? 20 : 16)
            .padding(.top, isLandscape ? 12 : 14)
            
            // Device ID Section
            VStack(spacing: isLandscape ? 12 : 16) {
                Text("device_id", tableName: "Devices")
                    .font(isLandscape ? .subheadline : .headline)
                    .foregroundColor(.secondary)
                
                if isLandscape {
                    HStack(spacing: 6) {
                        Text(currentDeviceID)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Button(action: {
                            UIPasteboard.general.string = currentDeviceID
                            if animationsAllowed {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCopiedAlert = true
                                }
                            } else {
                                showCopiedAlert = true
                            }

                            // Automatically hide alert after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if animationsAllowed {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showCopiedAlert = false
                                    }
                                } else {
                                    showCopiedAlert = false
                                }
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text(NSLocalizedString("copy_device_id", tableName: "Devices", comment: "Copy device ID to clipboard")))
                        .accessibilityHint(Text(NSLocalizedString("copy_device_id_hint", tableName: "Devices", comment: "Copies your device ID to the clipboard")))

                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_url_button_label", tableName: "Devices"))

                        Button(action: {
                            if MFMailComposeViewController.canSendMail() {
                                if let img = generateQRCodeImage() { qrImage = img }
                                showMailComposer = true
                            } else {
                                if let img = generateQRCodeImage() { qrImage = img }
                                showShareFallback = true
                            }
                        }) {
                            Image(systemName: "envelope")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_email_button_label", tableName: "Devices"))
                    }
                } else {
                    // Portrait: device id + copy on first row
                    HStack(spacing: 8) {
                        Text(currentDeviceID)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Button(action: {
                            UIPasteboard.general.string = currentDeviceID
                            if animationsAllowed {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCopiedAlert = true
                                }
                            } else {
                                showCopiedAlert = true
                            }

                            // Automatically hide alert after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if animationsAllowed {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showCopiedAlert = false
                                    }
                                } else {
                                    showCopiedAlert = false
                                }
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text(NSLocalizedString("copy_device_id", tableName: "Devices", comment: "Copy device ID to clipboard")))
                        .accessibilityHint(Text(NSLocalizedString("copy_device_id_hint", tableName: "Devices", comment: "Copies your device ID to the clipboard")))
                    }

                    // Portrait: share buttons on second row below
                    HStack(spacing: 16) {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_url_button_label", tableName: "Devices"))

                        Button(action: {
                            if MFMailComposeViewController.canSendMail() {
                                if let img = generateQRCodeImage() { qrImage = img }
                                showMailComposer = true
                            } else {
                                if let img = generateQRCodeImage() { qrImage = img }
                                showShareFallback = true
                            }
                        }) {
                            Image(systemName: "envelope")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_email_button_label", tableName: "Devices"))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, isLandscape ? 20 : 16)
            .padding(.top, isLandscape ? 10 : 12)
            
            VisitorHistorySection(
                viewModel: visitorHistoryViewModel,
                deviceStore: deviceStore,
                pendingDeviceItem: $pendingDeviceItem,
                isLandscape: isLandscape
            )
            .padding(.horizontal, isLandscape ? 20 : 16)
            .padding(.top, isLandscape ? 16 : 20)
            
            Spacer()
                .frame(height: isLandscape ? 20 : 30)
        }
    }

    private var qrContent: QRCodeShape {
        QRCodeShape(
            data: content.data(using: .utf8) ?? Data(),
            errorCorrection: correction
        )
    }

    private func generateQRCodeImage() -> UIImage? {
        if let qr = try? QRCode(utf8String: content, errorCorrection: correction) {
            return try? qr.uiImage(CGSize(width: 300, height: 300))
        }
        return nil
    }

    private var shareText: String {
        String(
            format: NSLocalizedString("share_device_email_body", tableName: "Devices", comment: "Body for sharing a device link via email or share sheet"),
            currentDeviceID,
            DeviceLinkResolver.urlString(for: currentDeviceID)
        )
    }

    private var ownDeviceID: String {
        currentDeviceID
    }

    private var displayedSloganText: String {
        ownDeviceSlogan.isEmpty ? NSLocalizedString("Device slogan", tableName: "Devices", comment: "Placeholder for the editable device info text.") : ownDeviceSlogan
    }

    private var sloganEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Device slogan", table: "Devices"), text: $sloganDraft)
                        .onChange(of: sloganDraft) { _, newValue in
                            let sanitizedDraft = MiataruAppAPI.sanitizeDeviceSloganDraft(newValue, maxLength: maxSloganLength)
                            if sanitizedDraft != newValue {
                                sloganDraft = sanitizedDraft
                            }
                        }

                    HStack {
                        Spacer()
                        Text(verbatim: "\(sloganDraft.count)/\(maxSloganLength)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("device_slogan_visibility_explanation", tableName: "Devices")
                        Text("Max 40 characters", tableName: "Common")
                    }
                }

                if let sloganErrorMessage, !sloganErrorMessage.isEmpty {
                    Section {
                        Text(sloganErrorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "Device Slogan", table: "Devices"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel", table: "Common")) {
                        showSloganEditor = false
                        sloganDraft = ownDeviceSlogan
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save", table: "Common")) {
                        Task {
                            await saveOwnDeviceSlogan()
                        }
                    }
                    .disabled(isSavingSlogan)
                }
            }
        }
    }

    @MainActor
    private func hydrateSloganFromCache() {
        ownDeviceSlogan = deviceSloganCacheStore.slogan(for: ownDeviceID) ?? ""
        sloganDraft = ownDeviceSlogan
    }

    @MainActor
    private func loadOwnDeviceSloganIfNeeded(forceRefresh: Bool = false) async {
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            sloganErrorMessage = NSLocalizedString("device_key_error_invalid_server", tableName: "Devices", comment: "Error when server URL is invalid")
            return
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }
        let deviceID = ownDeviceID

        let shouldRefresh = deviceSloganCacheStore.shouldRefresh(
            for: deviceID,
            minimumRefreshInterval: 300,
            force: forceRefresh
        )
        if !shouldRefresh {
            hydrateSloganFromCache()
            return
        }

        isLoadingSlogan = true
        defer { isLoadingSlogan = false }

        do {
            APIRequestCounter.shared.record(.getLocation)
            _ = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: [deviceID],
                requestingDeviceID: deviceID,
                requestingDeviceKey: deviceKey
            )
            hydrateSloganFromCache()
            sloganErrorMessage = nil
        } catch {
            hydrateSloganFromCache()
            if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                sloganErrorMessage = authMessage
            } else {
                sloganErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func saveOwnDeviceSlogan() async {
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            sloganErrorMessage = NSLocalizedString("device_key_error_invalid_server", tableName: "Devices", comment: "Error when server URL is invalid")
            return
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            sloganErrorMessage = NSLocalizedString("device_key_auth_required_message", tableName: "Devices", comment: "Message when device key authentication is required")
            return
        }

        let normalizedSlogan = MiataruAppAPI.cleanseDeviceSlogan(sloganDraft, maxLength: maxSloganLength)
        sloganDraft = normalizedSlogan
        isSavingSlogan = true
        defer { isSavingSlogan = false }

        do {
            _ = try await MiataruAppAPI.setDeviceSlogan(
                serverURL: serverURL,
                deviceID: ownDeviceID,
                deviceKey: deviceKey,
                slogan: normalizedSlogan
            )
            deviceSloganCacheStore.cacheSlogan(normalizedSlogan, for: ownDeviceID)
            deviceSloganCacheStore.markFreshNow(for: ownDeviceID)
            hydrateSloganFromCache()
            sloganErrorMessage = nil
            showSloganEditor = false
        } catch {
            if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                sloganErrorMessage = authMessage
            } else {
                sloganErrorMessage = NSLocalizedString("device_slogan_set_failed_try_again_later", tableName: "Devices", comment: "Fallback error when setting the device slogan failed."
                )
            }
        }
    }

    @MainActor
    private func synchronizeCurrentDeviceIdentity() -> Bool {
        let latestDeviceID = thisDeviceIDManager.shared.deviceID
        guard latestDeviceID.uppercased() != currentDeviceID.uppercased() else {
            return false
        }
        currentDeviceID = latestDeviceID
        content = DeviceLinkResolver.urlString(for: latestDeviceID)
        return true
    }
}

struct TrackingPauseSettingsRow: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: settings.isTrackingPaused ? "pause.circle.fill" : "timer")
                .font(.body.weight(.semibold))
                .foregroundColor(settings.isTrackingPaused ? .orange : .blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("tracking_pause_settings_title", tableName: "LocationTracking")
                    .font(.body)
                    .foregroundColor(.primary)

                Text("tracking_pause_settings_explanation", tableName: "LocationTracking")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let expiresAt = activePauseExpiresAt {
                    Text(Self.formattedStatus(expiresAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.top, 5)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    fileprivate var activePauseExpiresAt: Date? {
        guard let expiresAt = settings.trackingPauseExpiresAt,
              expiresAt > Date() else {
            return nil
        }
        return expiresAt
    }

    fileprivate static func formattedStatus(_ date: Date) -> String {
        String(
            format: NSLocalizedString(
                "tracking_pause_active_until_short_format",
                tableName: "LocationTracking",
                comment: "Short status for active server update pause. Argument: end date."
            ),
            localizedDateTimeString(from: date)
        )
    }

    static func localizedDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }
}

struct TrackingPauseDeviceListBanner: View {
    @ObservedObject private var settings = SettingsManager.shared
    let action: () -> Void

    var body: some View {
        if let expiresAt = activePauseExpiresAt {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "pause.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("tracking_pause_device_list_banner_title", tableName: "LocationTracking")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("tracking_pause_device_list_banner_message", tableName: "LocationTracking")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(expirationText(for: expiresAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 3)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .padding(.vertical, 6)
            .accessibilityIdentifier("devices_tracking_pause_banner")
            .accessibilityHint(Text("tracking_pause_device_list_banner_hint", tableName: "LocationTracking"))
        }
    }

    private var activePauseExpiresAt: Date? {
        guard let expiresAt = settings.trackingPauseExpiresAt,
              expiresAt > Date() else {
            return nil
        }
        return expiresAt
    }

    private func expirationText(for date: Date) -> String {
        String(
            format: NSLocalizedString(
                "tracking_pause_device_list_banner_active_until_format",
                tableName: "LocationTracking",
                comment: "Active server update pause line shown in the device list. Argument: end date."
            ),
            TrackingPauseSettingsRow.localizedDateTimeString(from: date)
        )
    }
}

struct TrackingPauseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @State private var now = Date()
    @State private var selectedDays = 0
    @State private var selectedHours = 2
    @State private var selectedMinutes = 0

    private let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    sheetHeader

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let expiresAt = activePauseExpiresAt {
                                activePauseCard(expiresAt: expiresAt)
                                    .padding(.horizontal)
                            }

                            Text("tracking_pause_duration_section_title", tableName: "LocationTracking")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, activePauseExpiresAt == nil ? 12 : 4)

                            durationPickerCard
                                .padding(.horizontal)

                            Text("tracking_pause_sheet_explanation", tableName: "LocationTracking")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal)
                        }
                        .padding(.top, 16)
                    }

                    Button {
                        LocationManager.shared.pauseTracking(forCustomDuration: TimeInterval(selectedDurationSeconds))
                        dismiss()
                    } label: {
                        Text("tracking_pause_start_button", tableName: "LocationTracking")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!isSelectionValid)
                    .padding(.horizontal)
                    .padding(.vertical, 18)
                    .accessibilityIdentifier("tracking_pause_start_button")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(minuteTicker) { tick in
                now = tick
            }
            .onChange(of: selectedDays) { _, newValue in
                if newValue == maximumDays {
                    selectedHours = 0
                    selectedMinutes = 0
                }
            }
        }
    }

    private var sheetHeader: some View {
        ZStack {
            Text("tracking_pause_sheet_title", tableName: "LocationTracking")
                .font(.headline)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .accessibilityLabel(Text("cancel", tableName: "Common"))

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var durationPickerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("", selection: $selectedDays) {
                    ForEach(0...maximumDays, id: \.self) { value in
                        Text(dayLabel(for: value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("tracking_pause_days_picker")

                Picker("", selection: $selectedHours) {
                    ForEach(0...23, id: \.self) { value in
                        Text(hourLabel(for: value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("tracking_pause_hours_picker")

                Picker("", selection: $selectedMinutes) {
                    ForEach(0...59, id: \.self) { value in
                        Text(minuteLabel(for: value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("tracking_pause_minutes_picker")
            }
            .frame(height: 182)
            .clipped()

            Divider()
                .padding(.horizontal)

            HStack(spacing: 8) {
                Text("tracking_pause_ends_label", tableName: "LocationTracking")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text(localizedDateString(from: selectedEndDate))
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    .accessibilityIdentifier("tracking_pause_end_date")

                Text(localizedTimeString(from: selectedEndDate))
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    .accessibilityIdentifier("tracking_pause_end_time")
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func activePauseCard(expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                String(
                    format: NSLocalizedString(
                        "tracking_pause_active_until_format",
                        tableName: "LocationTracking",
                        comment: "Server update pause active status. Argument: end date."
                    ),
                    TrackingPauseSettingsRow.localizedDateTimeString(from: expiresAt)
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            Button {
                LocationManager.shared.resumeTrackingFromPause(reason: "user resumed server updates from pause sheet")
                dismiss()
            } label: {
                Label(
                    String(localized: "tracking_pause_resume_now", table: "LocationTracking"),
                    systemImage: "play.circle"
                )
            }
            .accessibilityIdentifier("tracking_pause_resume_now_button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activePauseExpiresAt: Date? {
        guard let expiresAt = settings.trackingPauseExpiresAt,
              expiresAt > now else {
            return nil
        }
        return expiresAt
    }

    private var selectedDurationSeconds: Int {
        (selectedDays * 86_400) + (selectedHours * 3_600) + (selectedMinutes * 60)
    }

    private var selectedEndDate: Date {
        now.addingTimeInterval(TimeInterval(selectedDurationSeconds))
    }

    private var isSelectionValid: Bool {
        let duration = TimeInterval(selectedDurationSeconds)
        return duration >= TrackingPauseCustomDuration.minimumSeconds &&
            duration <= TrackingPauseCustomDuration.maximumSeconds
    }

    private var maximumDays: Int { 30 }

    private func dayLabel(for value: Int) -> String {
        String(format: NSLocalizedString("tracking_pause_day_picker_format", tableName: "LocationTracking", comment: "Day value in server update pause duration picker."), value)
    }

    private func hourLabel(for value: Int) -> String {
        String(format: NSLocalizedString("tracking_pause_hour_picker_format", tableName: "LocationTracking", comment: "Hour value in server update pause duration picker."), value)
    }

    private func minuteLabel(for value: Int) -> String {
        String(format: NSLocalizedString("tracking_pause_minute_picker_format", tableName: "LocationTracking", comment: "Minute value in server update pause duration picker."), value)
    }

    private func localizedDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private func localizedTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }
}

struct MailView: UIViewControllerRepresentable {
    let deviceID: String
    let qrImage: UIImage

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        let subject = NSLocalizedString("share_device_email_subject", tableName: "Devices", comment: "")
        let body = String(format: NSLocalizedString("share_device_email_body", tableName: "Devices", comment: ""), deviceID, DeviceLinkResolver.urlString(for: deviceID))
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = qrImage.pngData() {
            vc.addAttachmentData(data, mimeType: "image/png", fileName: "device-qrcode.png")
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    iPhone_MyDeviceQRCodeView()
}
