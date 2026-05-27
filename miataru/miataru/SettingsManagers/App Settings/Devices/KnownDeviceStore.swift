/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * KnownDeviceStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import UIKit
import Combine

// Falls erforderlich, KnownDevice importieren (bei getrennten Modulen):
// import miataru

class KnownDeviceStore: ObservableObject {
    static let shared = KnownDeviceStore()
    
    @Published var devices: [KnownDevice] = [] {
        didSet {
            guard !isInitializing && !isBatchUpdating else { return }
            setupSubscribers()
            save()
            WidgetDataSyncCoordinator.syncAllDevices()
        }
    }
    private let fileName = "knownDevices.plist"
    private var cancellables: [AnyCancellable] = []
    private var isInitializing = true
    private var isBatchUpdating = false

    private var fileURL: URL {
        AppDirectories.applicationSupportFile(named: fileName)
    }

    // Make init private for singleton
    private init() {
        self.devices = load()
        var shouldSaveAfterInitialization = normalizeDevicePositions()
        // Sicherstellen, dass das eigene Gerät immer in der Liste ist
        let myDeviceID = thisDeviceIDManager.shared.deviceID
        if !self.devices.contains(where: { $0.DeviceID == myDeviceID }) {
            let myDeviceName = NSLocalizedString("my_device", comment: "Name for the user's own device in the device list")
            let myDevice = KnownDevice(name: myDeviceName, deviceID: myDeviceID, color: UIColor.systemBlue)
            self.devices.insert(myDevice, at: 0)
            shouldSaveAfterInitialization = normalizeDevicePositions() || shouldSaveAfterInitialization
            debugLog("[DEBUG] Eigenes Gerät mit DeviceID \(myDeviceID) wurde automatisch als erstes Device hinzugefügt.")
        }
        setupSubscribers()
        if shouldSaveAfterInitialization {
            save()
        }
        isInitializing = false
    }

    private func setupSubscribers() {
        cancellables = []
        for device in devices {
            let c = device.objectWillChange
                .sink { [weak self] _ in
                    guard let self, !self.isInitializing && !self.isBatchUpdating else { return }
                    self.save()
                    WidgetDataSyncCoordinator.syncAllDevices()
                }
            cancellables.append(c)
        }
    }

    private func save() {
       do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            debugLog("Fehler beim Speichern der KnownDevices: \(error)")
        }
        //print("Speichern ist temporär deaktiviert - muss repariert werden!!!")
    }

    private func load() -> [KnownDevice] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let devices = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, KnownDevice.self, UIColor.self], from: data) as? [KnownDevice] {
                // Nach gespeicherter Reihenfolge sortieren
                return devices.enumerated()
                    .sorted {
                        if $0.element.KnownDevicesTablePosition == $1.element.KnownDevicesTablePosition {
                            return $0.offset < $1.offset
                        }
                        return $0.element.KnownDevicesTablePosition < $1.element.KnownDevicesTablePosition
                    }
                    .map(\.element)
            }
        } catch {
            debugLog("Fehler beim Laden der KnownDevices: \(error)")
        }
        return []
    }

    /// Fügt ein Gerät hinzu, wenn die DeviceID noch nicht existiert. Gibt true zurück, wenn erfolgreich, false bei Duplikat.
    @discardableResult
    func add(device: KnownDevice) -> Bool {
        let trimmedDeviceID = trimmedValue(device.DeviceID)
        guard !trimmedDeviceID.isEmpty else { return false }
        if self.device(matchingDeviceIDCaseInsensitive: device.DeviceID) != nil {
            return false
        }
        device.DeviceName = trimmedValue(device.DeviceName)
        device.DeviceID = trimmedDeviceID
        device.KnownDevicesTablePosition = devices.count
        devices.append(device)
        return true
    }

    func device(matchingDeviceIDCaseInsensitive rawDeviceID: String, excluding excludedDevice: KnownDevice? = nil) -> KnownDevice? {
        let normalizedID = normalizedDeviceID(rawDeviceID)
        guard !normalizedID.isEmpty else { return nil }
        return devices.first { device in
            guard device !== excludedDevice else { return false }
            return normalizedDeviceID(device.DeviceID) == normalizedID
        }
    }

    func devices(matchingNameCaseInsensitive rawDeviceName: String, excluding excludedDevice: KnownDevice? = nil) -> [KnownDevice] {
        let normalizedName = normalizedDeviceName(rawDeviceName)
        guard !normalizedName.isEmpty else { return [] }
        return devices.filter { device in
            guard device !== excludedDevice else { return false }
            return normalizedDeviceName(device.DeviceName) == normalizedName
        }
    }

    func hasCaseInsensitiveNameDuplicate(for device: KnownDevice) -> Bool {
        !devices(matchingNameCaseInsensitive: device.DeviceName, excluding: device).isEmpty
    }

    func hasCaseInsensitiveDeviceIDDuplicate(for device: KnownDevice) -> Bool {
        self.device(matchingDeviceIDCaseInsensitive: device.DeviceID, excluding: device) != nil
    }

    func hasCaseInsensitiveNameDuplicate(named rawDeviceName: String, excluding excludedDevice: KnownDevice? = nil) -> Bool {
        !devices(matchingNameCaseInsensitive: rawDeviceName, excluding: excludedDevice).isEmpty
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        isBatchUpdating = true
        devices.move(fromOffsets: source, toOffset: destination)
        // Reihenfolge-Index aktualisieren
        _ = normalizeDevicePositions()
        isBatchUpdating = false
        commitDeviceChanges()
    }

    func remove(atOffsets offsets: IndexSet) {
        // Get device IDs that will be removed
        let deviceIDsToRemove = offsets.map { devices[$0].DeviceID }
        
        // Remove devices from the list
        isBatchUpdating = true
        devices.remove(atOffsets: offsets)
        _ = normalizeDevicePositions()
        isBatchUpdating = false
        
        // Remove devices from all groups
        removeDevicesFromAllGroups(deviceIDs: deviceIDsToRemove)
        
        commitDeviceChanges()
    }
    
    func removeDevice(byID deviceID: String) {
        // Remove device from the list
        isBatchUpdating = true
        devices.removeAll { $0.DeviceID == deviceID }
        _ = normalizeDevicePositions()
        isBatchUpdating = false
        
        // Remove device from all groups
        removeDevicesFromAllGroups(deviceIDs: [deviceID])
        
        commitDeviceChanges()
    }
    
    private func removeDevicesFromAllGroups(deviceIDs: [String]) {
        let groupStore = DeviceGroupStore.shared
        
        for group in groupStore.groups {
            var changed = false
            for deviceID in deviceIDs {
                if group.deviceIDs.contains(deviceID) {
                    group.removeDevice(deviceID)
                    changed = true
                }
            }
            if changed {
                group.objectWillChange.send()
            }
        }
    }

    @discardableResult
    private func normalizeDevicePositions() -> Bool {
        var changed = false
        for (index, device) in devices.enumerated() {
            if device.KnownDevicesTablePosition != index {
                device.KnownDevicesTablePosition = index
                changed = true
            }
        }
        return changed
    }

    private func commitDeviceChanges() {
        setupSubscribers()
        save()
        WidgetDataSyncCoordinator.syncAllDevices()
    }

    private func trimmedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedDeviceID(_ deviceID: String) -> String {
        trimmedValue(deviceID).uppercased()
    }

    private func normalizedDeviceName(_ deviceName: String) -> String {
        trimmedValue(deviceName).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
} 
