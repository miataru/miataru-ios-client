//
//  DeviceIDManager.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 21.06.25.
//  Copyright © 2025 Miataru. All rights reserved.
//
import Foundation

class thisDeviceIDManager {
    static let shared = thisDeviceIDManager()
    private let legacyFileName = "deviceID.plist"
    private let modernFileName = "deviceIDmodern.txt"
    
    private var cachedDeviceID: String? = nil
    
    private init() {}
    
    /// Gibt die gespeicherte oder neu generierte deviceID zurück
    var deviceID: String {
        if let cached = cachedDeviceID {
            return cached
        }
        let loaded = loadDeviceID()!
        cachedDeviceID = loaded
        return loaded
    }

    private var appDirectory: URL? {
        guard let appSupportDir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
              let bundleID = Bundle.main.bundleIdentifier else {
            return nil
        }
        return appSupportDir.appendingPathComponent(bundleID)
    }
    
    private var legacyFileURL: URL? {
        return appDirectory?.appendingPathComponent(legacyFileName)
    }
    
    private var modernFileURL: URL? {
        return appDirectory?.appendingPathComponent(modernFileName)
    }
    
    private func ensureAppDirectoryExists() {
        guard let dir = appDirectory else { return }
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func saveDeviceID(_ id: String) {
        print("[DEBUG] Attempting to save deviceID: \(id)")
        ensureAppDirectoryExists()
        guard let modernURL = modernFileURL else {
            print("[DEBUG] modernFileURL is nil. Cannot save deviceID.")
            return
        }
        do {
            try id.write(to: modernURL, atomically: true, encoding: .utf8)
            print("[DEBUG] deviceID successfully saved to: \(modernURL.path)")
        } catch {
            print("[DEBUG] Error saving deviceID: \(error)")
        }
    }
    
    private func loadDeviceID() -> String? {
        print("[DEBUG] Attempting to load deviceID...")
        ensureAppDirectoryExists()
        guard let modernURL = modernFileURL else {
            print("[DEBUG] modernFileURL is nil. Cannot load deviceID.")
            return nil
        }
        // 1. Prüfe, ob das neue Format existiert
        if FileManager.default.fileExists(atPath: modernURL.path) {
            print("[DEBUG] Found modern deviceID file at: \(modernURL.path)")
            if let id = try? String(contentsOf: modernURL, encoding: .utf8) {
                print("[DEBUG] Loaded deviceID from modern file: \(id)")
                return id
            } else {
                print("[DEBUG] Failed to read deviceID from modern file.")
            }
        }
        // 2. Prüfe, ob das alte Format existiert und migriere ggf.
        guard let legacyURL = legacyFileURL else {
            print("[DEBUG] legacyFileURL is nil. Cannot check legacy deviceID.")
            return nil
        }
        if FileManager.default.fileExists(atPath: legacyURL.path),
           let data = try? Data(contentsOf: legacyURL),
           let legacyID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) as String? {
            print("[DEBUG] Found legacy deviceID file at: \(legacyURL.path). Migrating to modern format.")
            // Migriere ins neue Format
            saveDeviceID(legacyID)
            return legacyID
        }
        // 3. Nichts gefunden: Neue deviceID erzeugen, speichern und zurückgeben
        print("[DEBUG] No deviceID found. Generating new deviceID.")
        let newID = UUID().uuidString
        saveDeviceID(newID)
        return newID
    }
}
