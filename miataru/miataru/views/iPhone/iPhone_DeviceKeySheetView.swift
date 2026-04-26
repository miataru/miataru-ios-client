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
    @ObservedObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var groupStore = DeviceGroupStore.shared
    @ObservedObject private var sloganStore = DeviceSloganCacheStore.shared

    @State private var isBusy = false
    @State private var errorMessage: String? = nil
    @State private var showCopiedAlert = false
    @State private var showRestoreSheet = false
    @State private var showCustomKeySheet = false
    @State private var didAutoOpenCustomForMismatch = false
    @State private var keyCardState: KeyCardState

    init(showsMismatchWarning: Bool) {
        self.showsMismatchWarning = showsMismatchWarning
        let hasRuntimeAuthBlock = SettingsManager.shared.deviceKeyAuthBlocked
        let initialErrorMessage: String? = {
            if showsMismatchWarning {
                return String(localized: "device_key_auth_mismatch_message")
            }
            if hasRuntimeAuthBlock {
                return String(localized: "device_key_auth_runtime_error_message")
            }
            return nil
        }()
        _errorMessage = State(initialValue: initialErrorMessage)
        _keyCardState = State(initialValue: showsMismatchWarning ? .mismatch : (hasRuntimeAuthBlock ? .failure : .normal))
        _showCustomKeySheet = State(initialValue: showsMismatchWarning || hasRuntimeAuthBlock)
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
            .accessibilityIdentifier("device_key_sheet")
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
            .onAppear {
                if errorMessage == nil {
                    if showsMismatchWarning {
                        errorMessage = String(localized: "device_key_auth_mismatch_message")
                    } else if settings.deviceKeyAuthBlocked {
                        errorMessage = String(localized: "device_key_auth_runtime_error_message")
                    }
                }

                guard (showsMismatchWarning || settings.deviceKeyAuthBlocked), !didAutoOpenCustomForMismatch else { return }
                didAutoOpenCustomForMismatch = true
                if !showCustomKeySheet {
                    DispatchQueue.main.async {
                        showCustomKeySheet = true
                    }
                }
            }
            .sheet(isPresented: $showRestoreSheet) {
                DeviceKeyEntrySheet(
                    title: String(localized: "device_key_restore_title"),
                    message: String(localized: "device_key_restore_message"),
                    confirmTitle: String(localized: "device_key_restore_confirm"),
                    initialValue: settings.deviceKey ?? ""
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
                    emergencyWarningMessage: String(localized: "device_key_custom_emergency_explanation"),
                    emergencyButtonTitle: String(localized: "device_key_custom_emergency_button"),
                    emergencyConfirmTitle: String(localized: "device_key_custom_emergency_confirm_title"),
                    emergencyConfirmMessage: String(localized: "device_key_custom_emergency_confirm_message"),
                    emergencyConfirmActionTitle: String(localized: "device_key_custom_emergency_confirm_action"),
                    onEmergencyReset: {
                        let result = await regenerateDeviceIdentityAndKey()
                        if let result {
                            errorMessage = result
                            keyCardState = .failure
                        } else {
                            errorMessage = nil
                            keyCardState = .success
                        }
                        return result
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

            Text("device_key_long_press_admin_hint")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

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

            Text("device_key_long_press_admin_hint")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                Text("device_key_current_label")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    RevealableSensitiveValueField(value: settings.deviceKey ?? "")

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
        if let failure = await performSetDeviceKey(currentKey: nil, newKey: newKey) {
            errorMessage = failure.message
            keyCardState = .failure
            if failure.isForbidden {
                showCustomKeySheet = true
            }
        } else {
            errorMessage = nil
            keyCardState = .success
        }
    }

    private func regenerateDeviceIdentityAndKey() async -> String? {
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
        }

        let oldDeviceID = thisDeviceIDManager.shared.deviceID
        let snapshot = captureIdentityMigrationSnapshot(oldDeviceID: oldDeviceID)
        let newDeviceID = UUID().uuidString
        let newDeviceKey = UUID().uuidString
        let oldSlogan = sloganStore.slogan(for: oldDeviceID)
        var createdServerSideIdentity = false

        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await MiataruAppAPI.setDeviceKey(
                serverURL: serverURL,
                deviceID: newDeviceID,
                currentDeviceKey: nil,
                newDeviceKey: newDeviceKey
            )
            createdServerSideIdentity = true

            thisDeviceIDManager.shared.setDeviceID(newDeviceID)
            settings.deviceKey = newDeviceKey
            settings.deviceKeyLastChanged = Date()
            settings.deviceKeyAuthBlocked = false
            settings.deviceKeyAuthBlockedKey = nil
            if settings.lastOpenedDeviceID?.uppercased() == oldDeviceID.uppercased() {
                settings.lastOpenedDeviceID = newDeviceID
            }

            migrateKnownDevices(from: oldDeviceID, to: newDeviceID)
            migrateGroups(from: oldDeviceID, to: newDeviceID)
            migrateOwnCachedLocation(from: oldDeviceID, to: newDeviceID)
            sloganStore.migrateCachedEntry(from: oldDeviceID, to: newDeviceID)

            if let oldSlogan, !oldSlogan.isEmpty {
                _ = try await MiataruAppAPI.setDeviceSlogan(
                    serverURL: serverURL,
                    deviceID: newDeviceID,
                    deviceKey: newDeviceKey,
                    slogan: oldSlogan
                )
            }

            if let oldSlogan, !oldSlogan.isEmpty {
                sloganStore.cacheSlogan(oldSlogan, for: newDeviceID)
            }

            restoreRetainedSettings(
                from: snapshot.settingsSnapshot,
                oldDeviceID: oldDeviceID,
                activeDeviceID: newDeviceID,
                activeDeviceKey: newDeviceKey,
                activeDeviceKeyLastChanged: settings.deviceKeyLastChanged,
                activeDeviceKeyAuthBlocked: false,
                activeDeviceKeyAuthBlockedKey: nil
            )

            if snapshot.settingsSnapshot.allowedDeviceListEnabled {
                try await AllowedDeviceListManager.shared.activateAllowedDeviceList()
            }

            NotificationCenter.default.post(
                name: .deviceIdentityDidReset,
                object: nil,
                userInfo: ["newDeviceID": newDeviceID]
            )
            NotificationCenter.default.post(name: .deviceKeyAuthResolved, object: nil)
            restoreTrackingStateAfterAuthRecovery()
            return nil
        } catch {
            rollbackIdentityMigration(
                snapshot: snapshot,
                transientNewDeviceID: newDeviceID
            )
            var message = localizedMessage(for: error)
            if createdServerSideIdentity {
                message += "\n\n" + NSLocalizedString(
                    "device_key_emergency_server_side_hint",
                    comment: "Hint explaining that a newly created server identity might still exist"
                )
            }
            return message
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
        return result?.message
    }

    private func performRestoreValidation(currentKey: String?, newKey: String) async -> String? {
        guard let url = URL(string: settings.miataruServerURL) else {
            return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
        }

        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await MiataruAppAPI.setDeviceKey(
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
            restoreTrackingStateAfterAuthRecovery()
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

    private func performSetDeviceKey(currentKey: String?, newKey: String) async -> SetDeviceKeyFailure? {
        guard let url = URL(string: settings.miataruServerURL) else {
            return SetDeviceKeyFailure(
                message: NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid"),
                isForbidden: false
            )
        }

        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await MiataruAppAPI.setDeviceKey(
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
            restoreTrackingStateAfterAuthRecovery()
            return nil
        } catch let error as MiataruAPIClient.APIError {
            return SetDeviceKeyFailure(
                message: apiErrorMessage(error),
                isForbidden: isForbiddenError(error)
            )
        } catch {
            return SetDeviceKeyFailure(message: error.localizedDescription, isForbidden: false)
        }
    }

    private func captureIdentityMigrationSnapshot(oldDeviceID: String) -> DeviceIdentityMigrationSnapshot {
        DeviceIdentityMigrationSnapshot(
            oldDeviceID: oldDeviceID,
            oldDeviceKey: settings.deviceKey,
            oldDeviceKeyLastChanged: settings.deviceKeyLastChanged,
            oldDeviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            oldDeviceKeyAuthBlockedKey: settings.deviceKeyAuthBlockedKey,
            settingsSnapshot: captureSettingsSnapshot(),
            knownDevices: AllowedDeviceListManager.shared.captureSnapshot(),
            groups: groupStore.groups.map { group in
                DeviceGroupSnapshot(
                    groupName: group.groupName,
                    deviceIDs: group.deviceIDs,
                    groupPosition: group.groupPosition
                )
            }
        )
    }

    private func rollbackIdentityMigration(
        snapshot: DeviceIdentityMigrationSnapshot,
        transientNewDeviceID: String
    ) {
        thisDeviceIDManager.shared.setDeviceID(snapshot.oldDeviceID)
        restoreRetainedSettings(
            from: snapshot.settingsSnapshot,
            oldDeviceID: snapshot.oldDeviceID,
            activeDeviceID: snapshot.oldDeviceID,
            activeDeviceKey: snapshot.oldDeviceKey,
            activeDeviceKeyLastChanged: snapshot.oldDeviceKeyLastChanged,
            activeDeviceKeyAuthBlocked: snapshot.oldDeviceKeyAuthBlocked,
            activeDeviceKeyAuthBlockedKey: snapshot.oldDeviceKeyAuthBlockedKey
        )

        AllowedDeviceListManager.shared.restoreSnapshot(snapshot.knownDevices)
        restoreGroups(from: snapshot.groups)

        DeviceLocationCacheStore.shared.removeLocation(for: transientNewDeviceID)
        DeviceHistoryCacheStore.shared.removeHistory(for: transientNewDeviceID)
    }

    private func captureSettingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            disableDeviceAutolock: settings.disableDeviceAutolock,
            preventScreenRotation: settings.preventScreenRotation,
            indicateAccuracyOnMap: settings.indicateAccuracyOnMap,
            groupsZoomToFit: settings.groupsZoomToFit,
            miataruServerURL: settings.miataruServerURL,
            trackAndReportLocation: settings.trackAndReportLocation,
            trackAndReportLocationDisabledByDeviceKeyAuth: settings.trackAndReportLocationDisabledByDeviceKeyAuth,
            saveLocationHistoryOnServer: settings.saveLocationHistoryOnServer,
            locationDataRetentionTime: settings.locationDataRetentionTime,
            mapType: settings.mapType,
            mapUpdateInterval: settings.mapUpdateInterval,
            outsideMapUpdateInterval: settings.outsideMapUpdateInterval,
            mapZoomLevel: settings.mapZoomLevel,
            historyNumberOfDays: settings.historyNumberOfDays,
            locationActivityType: settings.locationActivityType,
            locationSensitivityLevel: settings.locationSensitivityLevel,
            frequentBackgroundLocationUpdatesEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            frequentBackgroundLocationDistanceFilter: settings.frequentBackgroundLocationDistanceFilter,
            frequentBackgroundLocationUpdateDuration: settings.frequentBackgroundLocationUpdateDuration,
            frequentBackgroundLocationUpdatesExpiresAt: settings.frequentBackgroundLocationUpdatesExpiresAt,
            frequentBackgroundLocationDeliveryMode: settings.frequentBackgroundLocationDeliveryMode,
            autoRefreshDeviceList: settings.autoRefreshDeviceList,
            unknownVisitorAlertsEnabled: settings.unknownVisitorAlertsEnabled,
            unknownVisitorAlertsPermissionDenied: settings.unknownVisitorAlertsPermissionDenied,
            showCurrentSpeedOnMap: settings.showCurrentSpeedOnMap,
            showOffscreenArrowsForOtherDevices: settings.showOffscreenArrowsForOtherDevices,
            showRouteProgress: settings.showRouteProgress,
            pulsingMapMarkers: settings.pulsingMapMarkers,
            automaticRouteUpdateDuringNavigation: settings.automaticRouteUpdateDuringNavigation,
            reverseGeocodingThresholdMeters: settings.reverseGeocodingThresholdMeters,
            navigationTransportType: settings.navigationTransportType,
            allowedDeviceListEnabled: settings.allowedDeviceListEnabled,
            oldLastOpenedDeviceID: settings.lastOpenedDeviceID,
            hasCompletedOnboarding: UserDefaults.standard.hasCompletedOnboarding,
            hasShownPostUpdateOnboarding: UserDefaults.standard.hasShownPostUpdateOnboarding
        )
    }

    private func restoreRetainedSettings(
        from snapshot: SettingsSnapshot,
        oldDeviceID: String,
        activeDeviceID: String,
        activeDeviceKey: String?,
        activeDeviceKeyLastChanged: Date?,
        activeDeviceKeyAuthBlocked: Bool,
        activeDeviceKeyAuthBlockedKey: String?
    ) {
        assignIfChanged(\.disableDeviceAutolock, snapshot.disableDeviceAutolock)
        assignIfChanged(\.preventScreenRotation, snapshot.preventScreenRotation)
        assignIfChanged(\.indicateAccuracyOnMap, snapshot.indicateAccuracyOnMap)
        assignIfChanged(\.groupsZoomToFit, snapshot.groupsZoomToFit)
        assignIfChanged(\.miataruServerURL, snapshot.miataruServerURL)
        assignIfChanged(\.trackAndReportLocation, snapshot.trackAndReportLocation)
        assignIfChanged(\.trackAndReportLocationDisabledByDeviceKeyAuth, snapshot.trackAndReportLocationDisabledByDeviceKeyAuth)
        assignIfChanged(\.saveLocationHistoryOnServer, snapshot.saveLocationHistoryOnServer)
        assignIfChanged(\.locationDataRetentionTime, snapshot.locationDataRetentionTime)
        assignIfChanged(\.mapType, snapshot.mapType)
        assignIfChanged(\.mapUpdateInterval, snapshot.mapUpdateInterval)
        assignIfChanged(\.outsideMapUpdateInterval, snapshot.outsideMapUpdateInterval)
        assignIfChanged(\.mapZoomLevel, snapshot.mapZoomLevel)
        assignIfChanged(\.historyNumberOfDays, snapshot.historyNumberOfDays)
        assignIfChanged(\.locationActivityType, snapshot.locationActivityType)
        assignIfChanged(\.locationSensitivityLevel, snapshot.locationSensitivityLevel)
        assignIfChanged(\.frequentBackgroundLocationUpdatesEnabled, snapshot.frequentBackgroundLocationUpdatesEnabled)
        assignIfChanged(\.frequentBackgroundLocationDistanceFilter, snapshot.frequentBackgroundLocationDistanceFilter)
        assignIfChanged(\.frequentBackgroundLocationUpdateDuration, snapshot.frequentBackgroundLocationUpdateDuration)
        assignIfChanged(\.frequentBackgroundLocationUpdatesExpiresAt, snapshot.frequentBackgroundLocationUpdatesExpiresAt)
        assignIfChanged(\.frequentBackgroundLocationDeliveryMode, snapshot.frequentBackgroundLocationDeliveryMode)
        assignIfChanged(\.autoRefreshDeviceList, snapshot.autoRefreshDeviceList)
        assignIfChanged(\.unknownVisitorAlertsEnabled, snapshot.unknownVisitorAlertsEnabled)
        assignIfChanged(\.unknownVisitorAlertsPermissionDenied, snapshot.unknownVisitorAlertsPermissionDenied)
        assignIfChanged(\.showCurrentSpeedOnMap, snapshot.showCurrentSpeedOnMap)
        assignIfChanged(\.showOffscreenArrowsForOtherDevices, snapshot.showOffscreenArrowsForOtherDevices)
        assignIfChanged(\.showRouteProgress, snapshot.showRouteProgress)
        assignIfChanged(\.pulsingMapMarkers, snapshot.pulsingMapMarkers)
        assignIfChanged(\.automaticRouteUpdateDuringNavigation, snapshot.automaticRouteUpdateDuringNavigation)
        assignIfChanged(\.reverseGeocodingThresholdMeters, snapshot.reverseGeocodingThresholdMeters)
        assignIfChanged(\.navigationTransportType, snapshot.navigationTransportType)
        assignIfChanged(\.allowedDeviceListEnabled, snapshot.allowedDeviceListEnabled)

        assignIfChanged(\.deviceKey, activeDeviceKey)
        assignIfChanged(\.deviceKeyLastChanged, activeDeviceKeyLastChanged)
        assignIfChanged(\.deviceKeyAuthBlocked, activeDeviceKeyAuthBlocked)
        assignIfChanged(\.deviceKeyAuthBlockedKey, activeDeviceKeyAuthBlockedKey)

        let resolvedLastOpenedDeviceID: String?
        if let oldLastOpenedDeviceID = snapshot.oldLastOpenedDeviceID,
           oldLastOpenedDeviceID.uppercased() == oldDeviceID.uppercased() {
            resolvedLastOpenedDeviceID = activeDeviceID
        } else {
            resolvedLastOpenedDeviceID = snapshot.oldLastOpenedDeviceID
        }
        assignIfChanged(\.lastOpenedDeviceID, resolvedLastOpenedDeviceID)

        if UserDefaults.standard.hasCompletedOnboarding != snapshot.hasCompletedOnboarding {
            UserDefaults.standard.hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        }
        if UserDefaults.standard.hasShownPostUpdateOnboarding != snapshot.hasShownPostUpdateOnboarding {
            UserDefaults.standard.hasShownPostUpdateOnboarding = snapshot.hasShownPostUpdateOnboarding
        }
    }

    private func assignIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<SettingsManager, T>,
        _ newValue: T
    ) {
        if settings[keyPath: keyPath] != newValue {
            settings[keyPath: keyPath] = newValue
        }
    }

    private func restoreTrackingStateAfterAuthRecovery() {
        if settings.trackAndReportLocationDisabledByDeviceKeyAuth {
            settings.trackAndReportLocationDisabledByDeviceKeyAuth = false
            if !settings.trackAndReportLocation {
                settings.trackAndReportLocation = true
            }
        }
        if settings.trackAndReportLocation {
            LocationManager.shared.startTracking()
        }
    }

    private func migrateKnownDevices(from oldDeviceID: String, to newDeviceID: String) {
        var devices = deviceStore.devices
        let normalizedOldDeviceID = oldDeviceID.uppercased()
        let ownIndex = devices.firstIndex { $0.DeviceID.uppercased() == normalizedOldDeviceID }

        if let ownIndex {
            let oldOwnDevice = devices.remove(at: ownIndex)
            let ownName = oldOwnDevice.DeviceName.isEmpty
                ? NSLocalizedString("my_device", comment: "Name for the user's own device in the device list")
                : oldOwnDevice.DeviceName

            let existingNames = Set(devices.map(\.DeviceName))
            let legacyName = uniqueLegacyDeviceName(baseName: ownName, existingNames: existingNames)

            let newOwnDevice = KnownDevice(
                name: ownName,
                deviceID: newDeviceID,
                color: oldOwnDevice.DeviceColor,
                hasCurrentLocationAccess: oldOwnDevice.hasCurrentLocationAccess,
                hasHistoryAccess: oldOwnDevice.hasHistoryAccess
            )
            newOwnDevice.DeviceIsInGroup = oldOwnDevice.DeviceIsInGroup

            let legacyDevice = KnownDevice(
                name: legacyName,
                deviceID: oldDeviceID,
                color: oldOwnDevice.DeviceColor,
                hasCurrentLocationAccess: oldOwnDevice.hasCurrentLocationAccess,
                hasHistoryAccess: oldOwnDevice.hasHistoryAccess
            )
            legacyDevice.DeviceIsInGroup = false

            devices.insert(newOwnDevice, at: ownIndex)
            devices.insert(legacyDevice, at: min(ownIndex + 1, devices.count))
        } else {
            let baseName = NSLocalizedString("my_device", comment: "Name for the user's own device in the device list")
            let existingNames = Set(devices.map(\.DeviceName))
            let legacyName = uniqueLegacyDeviceName(baseName: baseName, existingNames: existingNames)

            let newOwnDevice = KnownDevice(name: baseName, deviceID: newDeviceID, color: UIColor.systemBlue)
            let legacyDevice = KnownDevice(name: legacyName, deviceID: oldDeviceID, color: UIColor.systemBlue)

            devices.insert(newOwnDevice, at: 0)
            devices.insert(legacyDevice, at: min(1, devices.count))
        }

        for (index, device) in devices.enumerated() {
            device.KnownDevicesTablePosition = index
        }
        deviceStore.devices = devices
    }

    private func migrateGroups(from oldDeviceID: String, to newDeviceID: String) {
        let normalizedOldDeviceID = oldDeviceID.uppercased()
        for group in groupStore.groups {
            let containsOld = group.deviceIDs.contains { $0.uppercased() == normalizedOldDeviceID }
            guard containsOld else { continue }

            var updatedIDs = Set(group.deviceIDs.filter { $0.uppercased() != normalizedOldDeviceID })
            updatedIDs.insert(newDeviceID)
            group.deviceIDs = updatedIDs
        }
    }

    private func restoreGroups(from snapshots: [DeviceGroupSnapshot]) {
        let restoredGroups = snapshots
            .map { snapshot -> DeviceGroup in
                let group = DeviceGroup(name: snapshot.groupName)
                group.deviceIDs = snapshot.deviceIDs
                group.groupPosition = snapshot.groupPosition
                return group
            }
            .sorted { $0.groupPosition < $1.groupPosition }
        groupStore.groups = restoredGroups
    }

    private func migrateOwnCachedLocation(from oldDeviceID: String, to newDeviceID: String) {
        guard let oldLocation = DeviceLocationCacheStore.shared.getLocation(for: oldDeviceID) else { return }
        DeviceLocationCacheStore.shared.setLocation(
            for: newDeviceID,
            latitude: oldLocation.latitude,
            longitude: oldLocation.longitude,
            accuracy: oldLocation.accuracy,
            timestamp: oldLocation.timestamp,
            batteryLevel: oldLocation.batteryLevel,
            altitude: oldLocation.altitude,
            speed: oldLocation.speed
        )
        DeviceLocationCacheStore.shared.setPlacemark(
            for: newDeviceID,
            country: oldLocation.country,
            locality: oldLocation.locality,
            timeZone: oldLocation.timeZone
        )
    }

    private func uniqueLegacyDeviceName(baseName: String, existingNames: Set<String>) -> String {
        let suffix = String(localized: "device_key_old_device_suffix")
        let numberedSuffixFormat = String(localized: "device_key_old_device_suffix_numbered")

        var candidate = "\(baseName) \(suffix)"
        if !existingNames.contains(candidate) {
            return candidate
        }

        var index = 2
        while index < 10_000 {
            let numberedSuffix = String(format: numberedSuffixFormat, locale: Locale.current, index)
            candidate = "\(baseName) \(numberedSuffix)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }

        return "\(baseName) \(suffix)"
    }

    private func localizedMessage(for error: Error) -> String {
        if let apiError = error as? MiataruAPIClient.APIError {
            return apiErrorMessage(apiError)
        }
        return error.localizedDescription
    }

    private func isForbiddenError(_ error: MiataruAPIClient.APIError) -> Bool {
        guard case .serverError(let statusCode, _) = error else { return false }
        return statusCode == 403
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

private struct SetDeviceKeyFailure {
    let message: String
    let isForbidden: Bool
}

private struct DeviceGroupSnapshot {
    let groupName: String
    let deviceIDs: Set<String>
    let groupPosition: Int
}

private struct DeviceIdentityMigrationSnapshot {
    let oldDeviceID: String
    let oldDeviceKey: String?
    let oldDeviceKeyLastChanged: Date?
    let oldDeviceKeyAuthBlocked: Bool
    let oldDeviceKeyAuthBlockedKey: String?
    let settingsSnapshot: SettingsSnapshot
    let knownDevices: [KnownDeviceSnapshot]
    let groups: [DeviceGroupSnapshot]
}

private struct SettingsSnapshot {
    let disableDeviceAutolock: Bool
    let preventScreenRotation: Bool
    let indicateAccuracyOnMap: Bool
    let groupsZoomToFit: Bool
    let miataruServerURL: String
    let trackAndReportLocation: Bool
    let trackAndReportLocationDisabledByDeviceKeyAuth: Bool
    let saveLocationHistoryOnServer: Bool
    let locationDataRetentionTime: Int
    let mapType: Int
    let mapUpdateInterval: Int
    let outsideMapUpdateInterval: Int
    let mapZoomLevel: Int
    let historyNumberOfDays: Int
    let locationActivityType: Int
    let locationSensitivityLevel: Int
    let frequentBackgroundLocationUpdatesEnabled: Bool
    let frequentBackgroundLocationDistanceFilter: Int
    let frequentBackgroundLocationUpdateDuration: Int
    let frequentBackgroundLocationUpdatesExpiresAt: Date?
    let frequentBackgroundLocationDeliveryMode: Int
    let autoRefreshDeviceList: Bool
    let unknownVisitorAlertsEnabled: Bool
    let unknownVisitorAlertsPermissionDenied: Bool
    let showCurrentSpeedOnMap: Bool
    let showOffscreenArrowsForOtherDevices: Bool
    let showRouteProgress: Bool
    let pulsingMapMarkers: Bool
    let automaticRouteUpdateDuringNavigation: Bool
    let reverseGeocodingThresholdMeters: Int
    let navigationTransportType: Int
    let allowedDeviceListEnabled: Bool
    let oldLastOpenedDeviceID: String?
    let hasCompletedOnboarding: Bool
    let hasShownPostUpdateOnboarding: Bool
}

private struct DeviceKeyEntrySheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let initialValue: String
    let emergencyWarningMessage: String?
    let emergencyButtonTitle: String?
    let emergencyConfirmTitle: String?
    let emergencyConfirmMessage: String?
    let emergencyConfirmActionTitle: String?
    let onEmergencyReset: (() async -> String?)?
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var inputValue: String
    @State private var isSubmitting = false
    @State private var isRunningEmergencyReset = false
    @State private var showEmergencyConfirmation = false
    @State private var errorMessage: String? = nil

    init(title: String,
         message: String,
         confirmTitle: String,
         initialValue: String,
         emergencyWarningMessage: String? = nil,
         emergencyButtonTitle: String? = nil,
         emergencyConfirmTitle: String? = nil,
         emergencyConfirmMessage: String? = nil,
         emergencyConfirmActionTitle: String? = nil,
         onEmergencyReset: (() async -> String?)? = nil,
         onSubmit: @escaping (String) async -> String?) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.initialValue = initialValue
        self.emergencyWarningMessage = emergencyWarningMessage
        self.emergencyButtonTitle = emergencyButtonTitle
        self.emergencyConfirmTitle = emergencyConfirmTitle
        self.emergencyConfirmMessage = emergencyConfirmMessage
        self.emergencyConfirmActionTitle = emergencyConfirmActionTitle
        self.onEmergencyReset = onEmergencyReset
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
                    RevealableSensitiveInputField(
                        text: $inputValue,
                        placeholder: String(localized: "device_key_entry_placeholder")
                    )
                }

                Section {
                    Button(confirmTitle) {
                        Task { await submit() }
                    }
                    .disabled(isProcessing)
                }

                if let emergencyWarningMessage,
                   let emergencyButtonTitle,
                   onEmergencyReset != nil {
                    Section {
                        Text(emergencyWarningMessage)
                            .font(.footnote)
                            .foregroundColor(.red)

                        Button {
                            showEmergencyConfirmation = true
                        } label: {
                            Text(emergencyButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .foregroundStyle(.white)
                        .disabled(isProcessing)
                        .accessibilityIdentifier("device_key_custom_emergency_button")
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
            }
            .alert(
                emergencyConfirmTitle ?? String(localized: "device_key_custom_emergency_confirm_title"),
                isPresented: $showEmergencyConfirmation
            ) {
                Button("cancel_button_label", role: .cancel) {}
                Button(
                    emergencyConfirmActionTitle ?? String(localized: "device_key_custom_emergency_confirm_action"),
                    role: .destructive
                ) {
                    Task { await runEmergencyReset() }
                }
            } message: {
                Text(emergencyConfirmMessage ?? String(localized: "device_key_custom_emergency_confirm_message"))
            }
        }
    }

    private var isProcessing: Bool {
        isSubmitting || isRunningEmergencyReset
    }

    private func runEmergencyReset() async {
        guard let onEmergencyReset else { return }
        isRunningEmergencyReset = true
        let error = await onEmergencyReset()
        isRunningEmergencyReset = false
        if let error {
            errorMessage = error
        } else {
            dismiss()
        }
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

private struct RevealableSensitiveValueField: View {
    let value: String

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Text(displayValue)
                .font(.system(.caption, design: .monospaced))
                .privacySensitive()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isRevealed ? "Hide DeviceKey" : "Show DeviceKey"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var displayValue: String {
        guard !value.isEmpty else { return "" }
        return isRevealed ? value : String(repeating: "•", count: max(value.count, 8))
    }
}

private struct RevealableSensitiveInputField: View {
    @Binding var text: String
    let placeholder: String

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .font(.system(.body, design: .monospaced))
            .privacySensitive()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isRevealed ? "Hide DeviceKey" : "Show DeviceKey"))
        }
    }
}

#Preview {
    iPhone_DeviceKeySheetView(showsMismatchWarning: true)
}
