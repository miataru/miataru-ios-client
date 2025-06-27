//
//  DeviceIDManager.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 21.06.25.
//  Copyright © 2025 Miataru. All rights reserved.
//


import Foundation
import UIKit

class thisDeviceIDManager {
    static let shared = thisDeviceIDManager()
    private let deviceIDFileName = "deviceID.plist"
    
    private init() {}
    
    /// Gibt die gespeicherte oder neu generierte deviceID zurück
    var deviceID: String {
        if let savedID = loadDeviceID() {
            return savedID
        } else {
            let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            saveDeviceID(newID)
            return newID
        }
    }
    
    /// Pfad zur deviceID.plist im Application Support-Ordner
    private var deviceIDFilePath: String {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "miataru"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        
        // Ordner anlegen, falls nicht vorhanden
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        return appDirectory.appendingPathComponent(deviceIDFileName).path
    }
    
    /// deviceID speichern
    private func saveDeviceID(_ id: String) {
        do {
            try id.write(toFile: deviceIDFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Fehler beim Speichern der deviceID: \(error)")
        }
    }
    
    /// deviceID laden
    private func loadDeviceID() -> String? {
        return try? String(contentsOfFile: deviceIDFilePath, encoding: .utf8)
    }
}
