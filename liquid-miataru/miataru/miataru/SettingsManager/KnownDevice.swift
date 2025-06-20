//
//  KnownDevice.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//  Copyright © 2025 Miataru. All rights reserved.
//


import Foundation

@objc(KnownDevice)
class KnownDevice: NSObject, NSCoding, NSSecureCoding {
    @objc var DeviceName: String
    @objc var DeviceID: String
    @objc var DeviceIsInGroup: Bool = false
    @objc var KnownDevicesTablePosition: Int = 0
    
    init(name: String, deviceID: String) {
        self.DeviceName = name
        self.DeviceID = deviceID
    }
    private let fileName = "knownDevices.plist"

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
    
    required init?(coder aDecoder: NSCoder) {
        self.DeviceName = aDecoder.decodeObject(forKey: "DeviceName") as? String ?? ""
        self.DeviceID = aDecoder.decodeObject(forKey: "DeviceID") as? String ?? ""
        self.DeviceIsInGroup = aDecoder.decodeBool(forKey: "DeviceIsInGroup")
        self.KnownDevicesTablePosition = aDecoder.decodeInteger(forKey: "KnownDevicesTablePosition")
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(DeviceName, forKey: "DeviceName")
        aCoder.encode(DeviceID, forKey: "DeviceID")
        aCoder.encode(DeviceIsInGroup, forKey: "DeviceIsInGroup")
        aCoder.encode(KnownDevicesTablePosition, forKey: "KnownDevicesTablePosition")
    }

    static var supportsSecureCoding: Bool {
        return true
    }
}

class KnownDeviceStore {
    static let shared = KnownDeviceStore()
    private let fileName = "knownDevices.plist"

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

    func save(devices: [KnownDevice]) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Fehler beim Speichern der KnownDevices: \(error)")
        }
    }

    func load() -> [KnownDevice] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let devices = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, KnownDevice.self], from: data) as? [KnownDevice] {
                return devices
            }
        } catch {
            print("Fehler beim Laden der KnownDevices: \(error)")
        }
        return []
    }
}
