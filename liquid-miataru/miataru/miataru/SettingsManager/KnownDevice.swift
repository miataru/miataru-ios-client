//
//  KnownDevice.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//  Copyright © 2025 Miataru. All rights reserved.
//


import Foundation

// Beispiel für ein KnownDevice-Objekt, das NSSecureCoding unterstützt
class KnownDevice: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool = true

    var deviceName: String
    var deviceID: String

    init(deviceName: String, deviceID: String) {
        self.deviceName = deviceName
        self.deviceID = deviceID
    }

    required convenience init?(coder aDecoder: NSCoder) {
        guard let deviceName = aDecoder.decodeObject(forKey: "deviceName") as? String,
              let deviceID = aDecoder.decodeObject(forKey: "deviceID") as? String else {
            return nil
        }
        self.init(deviceName: deviceName, deviceID: deviceID)
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(deviceName, forKey: "deviceName")
        aCoder.encode(deviceID, forKey: "deviceID")
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