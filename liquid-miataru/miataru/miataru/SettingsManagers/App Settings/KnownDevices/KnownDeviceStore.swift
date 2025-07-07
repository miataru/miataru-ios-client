import Foundation
import UIKit
import Combine

// Falls erforderlich, KnownDevice importieren (bei getrennten Modulen):
// import miataru

class KnownDeviceStore: ObservableObject {
    static let shared = KnownDeviceStore()
    
    @Published var devices: [KnownDevice] = [] {
        didSet {
            setupSubscribers()
            save()
        }
    }
    private let fileName = "knownDevices.plist"
    private var cancellables: [AnyCancellable] = []

    private var fileURL: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        // Verzeichnis anlegen, falls nicht vorhanden
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectory.appendingPathComponent(fileName)
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
            print("[DEBUG] Eigenes Gerät mit DeviceID \(myDeviceID) wurde automatisch als erstes Device hinzugefügt.")
            save()
        }
        setupSubscribers()
    }

    private func setupSubscribers() {
        cancellables = []
        for device in devices {
            let c = device.objectWillChange
                .sink { [weak self] _ in
                    self?.save()
                }
            cancellables.append(c)
        }
    }

    private func save() {
       do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Fehler beim Speichern der KnownDevices: \(error)")
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
            print("Fehler beim Laden der KnownDevices: \(error)")
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
