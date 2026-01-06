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
            guard !isInitializing else { return }
            setupSubscribers()
            save()
            WidgetDataSyncCoordinator.syncAllDevices()
        }
    }
    private let fileName = "knownDevices.plist"
    private var cancellables: [AnyCancellable] = []
    private var isInitializing = true

    private var fileURL: URL {
        AppDirectories.applicationSupportFile(named: fileName)
    }

    // Make init private for singleton
    private init() {
        self.devices = load()
        // Sicherstellen, dass das eigene Gerät immer in der Liste ist
        let myDeviceID = thisDeviceIDManager.shared.deviceID
        if !self.devices.contains(where: { $0.DeviceID == myDeviceID }) {
            let myDeviceName = NSLocalizedString("my_device", comment: "Name for the user's own device in the device list")
            let myDevice = KnownDevice(name: myDeviceName, deviceID: myDeviceID, color: UIColor.systemBlue)
            self.devices.insert(myDevice, at: 0)
            debugLog("[DEBUG] Eigenes Gerät mit DeviceID \(myDeviceID) wurde automatisch als erstes Device hinzugefügt.")
            save()
        }
        setupSubscribers()
        isInitializing = false
    }

    private func setupSubscribers() {
        cancellables = []
        for device in devices {
            let c = device.objectWillChange
                .sink { [weak self] _ in
                    self?.save()
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
                return devices.sorted { $0.KnownDevicesTablePosition < $1.KnownDevicesTablePosition }
            }
        } catch {
            debugLog("Fehler beim Laden der KnownDevices: \(error)")
        }
        return []
    }

    /// Fügt ein Gerät hinzu, wenn die DeviceID noch nicht existiert. Gibt true zurück, wenn erfolgreich, false bei Duplikat.
    @discardableResult
    func add(device: KnownDevice) -> Bool {
        if devices.contains(where: { $0.DeviceID == device.DeviceID }) {
            return false
        }
        devices.append(device)
        return true
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        devices.move(fromOffsets: source, toOffset: destination)
        // Reihenfolge-Index aktualisieren
        for (index, device) in devices.enumerated() {
            device.KnownDevicesTablePosition = index
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        // Get device IDs that will be removed
        let deviceIDsToRemove = offsets.map { devices[$0].DeviceID }
        
        // Remove devices from the list
        devices.remove(atOffsets: offsets)
        
        // Remove devices from all groups
        removeDevicesFromAllGroups(deviceIDs: deviceIDsToRemove)
        
        save()
    }
    
    func removeDevice(byID deviceID: String) {
        // Remove device from the list
        devices.removeAll { $0.DeviceID == deviceID }
        
        // Remove device from all groups
        removeDevicesFromAllGroups(deviceIDs: [deviceID])
        
        save()
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
} 
