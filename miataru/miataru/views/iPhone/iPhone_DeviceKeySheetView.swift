/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_DeviceKeySheetView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 31.01.26.
 */

import SwiftUI
import MiataruAPIClient
import UIKit

struct iPhone_DeviceKeySheetView: View {
    let showsMismatchWarning: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SettingsManager.shared

    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    @State private var showCopiedAlert = false
    @State private var showRestoreSheet = false
    @State private var showCustomKeySheet = false
    @State private var keyCardState: KeyCardState

    init(showsMismatchWarning: Bool) {
        self.showsMismatchWarning = showsMismatchWarning
        _keyCardState = State(initialValue: showsMismatchWarning ? .mismatch : .normal)
    }

    private var hasDeviceKey: Bool {
        guard let key = settings.deviceKey else { return false }
        return !key.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                if hasDeviceKey {
                    deviceKeySetContent
                } else {
                    deviceKeyUnsetContent
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .navigationTitle("device_key_title")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_button_label") {
                        dismiss()
                    }
                }
            }
            .overlay(copyOverlay)
            .sheet(isPresented: $showRestoreSheet) {
                DeviceKeyEntrySheet(
                    title: String(localized: "device_key_restore_title"),
                    message: String(localized: "device_key_restore_message"),
                    confirmTitle: String(localized: "device_key_restore_confirm"),
                    initialValue: settings.deviceKey ?? "",
                    showsRegenerateButton: false,
                    onRegenerate: nil
                ) { enteredKey in
                    await restoreDeviceKey(enteredKey)
                }
            }
            .sheet(isPresented: $showCustomKeySheet) {
                DeviceKeyEntrySheet(
                    title: String(localized: "device_key_custom_title"),
                    message: String(localized: "device_key_custom_message"),
                    confirmTitle: String(localized: "device_key_custom_confirm"),
                    initialValue: settings.deviceKey ?? "",
                    showsRegenerateButton: true,
                    onRegenerate: {
                        await regenerateDeviceKey()
                    }
                ) { enteredKey in
                    await setCustomDeviceKey(enteredKey)
                }
            }
        }
    }

    private var deviceKeyUnsetContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.card")
                .font(.system(size: 104))
                .foregroundColor(keyCardColor)
                .padding(.top, 8)
                .frame(width: 140, height: 140, alignment: .center)
                .contentShape(Rectangle())
                .onLongPressGesture {
                    showCustomKeySheet = true
                }

            if showsMismatchWarning {
                Text("device_key_mismatch_explanation")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Text("device_key_intro_text")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)

            Button {
                Task { await generateAndSetDeviceKey() }
            } label: {
                if isBusy {
                    ProgressView()
                } else {
                    Text("device_key_generate_button")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(isBusy)
            .padding(.horizontal, 16)
        }
    }

    private var deviceKeySetContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.card")
                .font(.system(size: 104))
                .foregroundColor(keyCardColor)
                .padding(.top, 8)
                .frame(width: 140, height: 140, alignment: .center)
                .contentShape(Rectangle())
                .onLongPressGesture {
                    showCustomKeySheet = true
                }

            if showsMismatchWarning {
                Text("device_key_mismatch_explanation")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 8) {
                Text("device_key_current_label")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(settings.deviceKey ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Button(action: copyDeviceKey) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(Text("device_key_copy_label"))
                    .accessibilityHint(Text("device_key_copy_hint"))
                }
            }
            .padding(.horizontal, 16)

            if let lastChangedText = formattedLastChanged() {
                Text(String(format: NSLocalizedString("device_key_last_changed", comment: ""), lastChangedText))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }

            Button("device_key_restore_button") {
                showRestoreSheet = true
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(isBusy)
            .padding(.horizontal, 16)
        }
    }

    private var copyOverlay: some View {
        Group {
            if showCopiedAlert {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("device_key_copied")
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
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .zIndex(1)
            }
        }
    }

    private func copyDeviceKey() {
        guard let key = settings.deviceKey, !key.isEmpty else { return }
        UIPasteboard.general.string = key
        withAnimation(.easeInOut(duration: 0.3)) {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopiedAlert = false
            }
        }
    }

    private func formattedLastChanged() -> String? {
        guard let date = settings.deviceKeyLastChanged else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func generateAndSetDeviceKey() async {
        let newKey = UUID().uuidString
        if let error = await performSetDeviceKey(currentKey: nil, newKey: newKey) {
            errorMessage = error
            keyCardState = .failure
        } else {
            errorMessage = nil
            keyCardState = .success
        }
    }

    private func regenerateDeviceKey() async {
        guard let currentKey = settings.deviceKey else { return }
        let newKey = UUID().uuidString
        if let error = await performSetDeviceKey(currentKey: currentKey, newKey: newKey) {
            errorMessage = error
            keyCardState = .failure
        } else {
            errorMessage = nil
            keyCardState = .success
        }
    }

    private func restoreDeviceKey(_ enteredKey: String) async -> String? {
        let trimmed = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateDeviceKey(trimmed) {
            keyCardState = .failure
            return error
        }
        let result = await performRestoreValidation(currentKey: trimmed, newKey: trimmed)
        if result == nil {
            errorMessage = nil
            keyCardState = .success
        } else {
            keyCardState = .failure
        }
        return result
    }

    private func setCustomDeviceKey(_ enteredKey: String) async -> String? {
        let trimmed = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validateDeviceKey(trimmed) {
            keyCardState = .failure
            return error
        }
        guard let currentKey = settings.deviceKey, !currentKey.isEmpty else {
            keyCardState = .failure
            return NSLocalizedString("device_key_missing_current", comment: "Error when current key is missing")
        }
        let result = await performSetDeviceKey(currentKey: currentKey, newKey: trimmed)
        if result == nil {
            errorMessage = nil
            keyCardState = .success
        } else {
            keyCardState = .failure
        }
        return result
    }

    private func performRestoreValidation(currentKey: String?, newKey: String) async -> String? {
        guard let url = URL(string: settings.miataruServerURL) else {
            return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
        }

        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await MiataruAPIClient.setDeviceKey(
                serverURL: url,
                deviceID: thisDeviceIDManager.shared.deviceID,
                currentDeviceKey: currentKey,
                newDeviceKey: newKey
            )
            settings.deviceKey = newKey
            settings.deviceKeyLastChanged = Date()
            settings.deviceKeyAuthBlocked = false
            settings.deviceKeyAuthBlockedKey = nil
            NotificationCenter.default.post(name: .deviceKeyAuthResolved, object: nil)
            if settings.trackAndReportLocation {
                LocationManager.shared.startTracking()
            }
            return nil
        } catch let error as MiataruAPIClient.APIError {
            switch error {
            case .serverError:
                return NSLocalizedString("device_key_restore_server_error", comment: "Server rejected DeviceKey during restore")
            default:
                return apiErrorMessage(error)
            }
        } catch {
            return error.localizedDescription
        }
    }

    private func validateDeviceKey(_ key: String) -> String? {
        if key.isEmpty {
            return NSLocalizedString("device_key_error_empty", comment: "Error when device key is empty")
        }
        if key.count > 256 {
            return NSLocalizedString("device_key_error_too_long", comment: "Error when device key exceeds max length")
        }
        return nil
    }

    private func performSetDeviceKey(currentKey: String?, newKey: String) async -> String? {
        guard let url = URL(string: settings.miataruServerURL) else {
            return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
        }

        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await MiataruAPIClient.setDeviceKey(
                serverURL: url,
                deviceID: thisDeviceIDManager.shared.deviceID,
                currentDeviceKey: currentKey,
                newDeviceKey: newKey
            )
            settings.deviceKey = newKey
            settings.deviceKeyLastChanged = Date()
            settings.deviceKeyAuthBlocked = false
            settings.deviceKeyAuthBlockedKey = nil
            NotificationCenter.default.post(name: .deviceKeyAuthResolved, object: nil)
            if settings.trackAndReportLocation {
                LocationManager.shared.startTracking()
            }
            return nil
        } catch let error as MiataruAPIClient.APIError {
            return apiErrorMessage(error)
        } catch {
            return error.localizedDescription
        }
    }

    private func apiErrorMessage(_ error: MiataruAPIClient.APIError) -> String {
        switch error {
        case .serverError(_, let message):
            return message
        case .invalidURL:
            return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
        case .invalidResponse:
            return NSLocalizedString("device_key_error_invalid_response", comment: "Error when server response is invalid")
        case .encodingError:
            return NSLocalizedString("device_key_error_encoding", comment: "Error when request encoding fails")
        case .decodingError:
            return NSLocalizedString("device_key_error_decoding", comment: "Error when response decoding fails")
        case .requestFailed:
            return NSLocalizedString("device_key_error_request_failed", comment: "Error when request fails")
        }
    }

    private var keyCardColor: Color {
        switch keyCardState {
        case .success:
            return .green
        case .failure, .mismatch:
            return .red
        case .normal:
            return .blue
        }
    }
}

private enum KeyCardState {
    case normal
    case mismatch
    case success
    case failure
}

private struct DeviceKeyEntrySheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let initialValue: String
    let showsRegenerateButton: Bool
    let onRegenerate: (() async -> Void)?
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var inputValue: String
    @State private var isSubmitting = false
    @State private var isRegenerating = false
    @State private var errorMessage: String? = nil

    init(title: String,
         message: String,
         confirmTitle: String,
         initialValue: String,
         showsRegenerateButton: Bool,
         onRegenerate: (() async -> Void)?,
         onSubmit: @escaping (String) async -> String?) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.initialValue = initialValue
        self.showsRegenerateButton = showsRegenerateButton
        self.onRegenerate = onRegenerate
        self.onSubmit = onSubmit
        _inputValue = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField("device_key_entry_placeholder", text: $inputValue)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                if showsRegenerateButton {
                    Section {
                        Button("device_key_regenerate_button") {
                            Task { await regenerateDeviceKey() }
                        }
                        .disabled(isSubmitting || isRegenerating)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button_label") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isRegenerating)
                }
            }
        }
    }

    private func regenerateDeviceKey() async {
        guard let onRegenerate else { return }
        isRegenerating = true
        await onRegenerate()
        dismiss()
    }

    private func submit() async {
        isSubmitting = true
        let error = await onSubmit(inputValue)
        if let error {
            errorMessage = error
            isSubmitting = false
        } else {
            dismiss()
        }
    }
}

#Preview {
    iPhone_DeviceKeySheetView(showsMismatchWarning: true)
}
