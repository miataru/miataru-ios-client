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

    @State var content: String = "miataru://" + thisDeviceIDManager.shared.deviceID
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

    private let maxSloganLength = 40

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
                .refreshable {
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: true, force: true)
                }
                .onAppear {
                    isVisible = true
                    hydrateSloganFromCache()
                    if visitorHistoryViewModel.visitors.isEmpty {
                        Task {
                            await visitorHistoryViewModel.loadVisitorHistory(showLoading: true)
                        }
                    }
                    Task {
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
                        await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
                        await loadOwnDeviceSloganIfNeeded()
                    }
                }
                .navigationTitle("my_device")
                .navigationBarTitleDisplayMode(isLandscape ? .inline : .large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            showDeviceKeySheet = true
                        }) {
                            Image(systemName: "key.card")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .accessibilityLabel(Text("device_key_button_label"))
                        .accessibilityHint(Text("device_key_button_hint"))
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
                                
                                Text("device_id_copied_to_clipboard")
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
                        deviceID: thisDeviceIDManager.shared.deviceID,
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
                        prefillDeviceID: item.deviceID
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
                
                // Title and explanation
                VStack(spacing: isLandscape ? 8 : 12) {
                    Text("my_device_qr_code")
                        .font(isLandscape ? .title2 : .title)
                        .multilineTextAlignment(.center)
                    
                    Text("qr_code_explanation")
                        .font(isLandscape ? .caption : .body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, isLandscape ? 40 : 20)
                }
            }
            .padding(.top, isLandscape ? 12 : 16)
            
            // Device ID Section
            VStack(spacing: isLandscape ? 12 : 16) {
                Text("device_id")
                    .font(isLandscape ? .subheadline : .headline)
                    .foregroundColor(.secondary)
                
                if isLandscape {
                    HStack(spacing: 6) {
                        Text(thisDeviceIDManager.shared.deviceID)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Button(action: {
                            UIPasteboard.general.string = thisDeviceIDManager.shared.deviceID
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
                        .accessibilityLabel(Text(NSLocalizedString("copy_device_id", comment: "Copy device ID to clipboard")))
                        .accessibilityHint(Text(NSLocalizedString("copy_device_id_hint", comment: "Copies your device ID to the clipboard")))

                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_url_button_label"))

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
                        .accessibilityLabel(Text("share_device_email_button_label"))
                    }
                } else {
                    // Portrait: device id + copy on first row
                    HStack(spacing: 8) {
                        Text(thisDeviceIDManager.shared.deviceID)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Button(action: {
                            UIPasteboard.general.string = thisDeviceIDManager.shared.deviceID
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
                        .accessibilityLabel(Text(NSLocalizedString("copy_device_id", comment: "Copy device ID to clipboard")))
                        .accessibilityHint(Text(NSLocalizedString("copy_device_id_hint", comment: "Copies your device ID to the clipboard")))
                    }

                    // Portrait: share buttons on second row below
                    HStack(spacing: 16) {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Text("share_device_url_button_label"))

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
                        .accessibilityLabel(Text("share_device_email_button_label"))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, isLandscape ? 20 : 16)
            .padding(.top, isLandscape ? 10 : 12)

            VStack(spacing: isLandscape ? 10 : 12) {
                Text("Device Slogan")
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
            format: NSLocalizedString("share_device_email_body", comment: "Body for sharing a device link via email or share sheet"),
            thisDeviceIDManager.shared.deviceID,
            "miataru://\(thisDeviceIDManager.shared.deviceID)"
        )
    }

    private var ownDeviceID: String {
        thisDeviceIDManager.shared.deviceID
    }

    private var displayedSloganText: String {
        ownDeviceSlogan.isEmpty ? NSLocalizedString("Device slogan", comment: "Placeholder for the editable device info text.") : ownDeviceSlogan
    }

    private var sloganEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Device slogan", text: $sloganDraft)
                        .onChange(of: sloganDraft) { _, newValue in
                            if newValue.count > maxSloganLength {
                                sloganDraft = String(newValue.prefix(maxSloganLength))
                            }
                        }

                    HStack {
                        Spacer()
                        Text("\(sloganDraft.count)/\(maxSloganLength)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Max 40 characters")
                }

                if let sloganErrorMessage, !sloganErrorMessage.isEmpty {
                    Section {
                        Text(sloganErrorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Device Slogan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        showSloganEditor = false
                        sloganDraft = ownDeviceSlogan
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
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
    private func loadOwnDeviceSloganIfNeeded() async {
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            sloganErrorMessage = NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
            return
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }

        isLoadingSlogan = true
        defer { isLoadingSlogan = false }

        let fetchError: Error?
        if deviceSloganCacheStore.isKnown(for: ownDeviceID) {
            fetchError = await deviceSloganCacheStore.refreshSloganIfStale(
                for: ownDeviceID,
                serverURL: serverURL,
                requestingDeviceID: ownDeviceID,
                requestingDeviceKey: deviceKey,
                minimumRefreshInterval: 300
            )
        } else {
            fetchError = await deviceSloganCacheStore.fetchSloganIfNeeded(
                for: ownDeviceID,
                serverURL: serverURL,
                requestingDeviceID: ownDeviceID,
                requestingDeviceKey: deviceKey
            )
        }
        hydrateSloganFromCache()
        if let fetchError {
            if let authMessage = DeviceKeyAuthHandler.handle(error: fetchError) {
                sloganErrorMessage = authMessage
            } else {
                sloganErrorMessage = fetchError.localizedDescription
            }
        } else {
            sloganErrorMessage = nil
        }
    }

    @MainActor
    private func saveOwnDeviceSlogan() async {
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            sloganErrorMessage = NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
            return
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            sloganErrorMessage = NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
            return
        }

        let normalizedSlogan = String(sloganDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSloganLength))
        isSavingSlogan = true
        defer { isSavingSlogan = false }

        do {
            _ = try await MiataruAPIClient.setDeviceSlogan(
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
                sloganErrorMessage = error.localizedDescription
            }
        }
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
        let subject = NSLocalizedString("share_device_email_subject", comment: "")
        let body = String(format: NSLocalizedString("share_device_email_body", comment: ""), deviceID, "miataru://\(deviceID)")
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
