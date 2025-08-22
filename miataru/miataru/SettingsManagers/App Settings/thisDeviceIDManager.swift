/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * thisDeviceIDManager.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

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
        // Safely attempt to load the persisted ID; fall back to generating
        // and storing a new one if loading fails for any reason.
        guard let loaded = loadDeviceID() else {
            // Fallback: create a fresh ID to avoid crashes on startup
            let newID = UUID().uuidString
            saveDeviceID(newID)
            cachedDeviceID = newID
            return newID
        }
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
        debugLog("[DEBUG] Attempting to save deviceID: \(id)")
        ensureAppDirectoryExists()
        guard let modernURL = modernFileURL else {
            debugLog("[DEBUG] modernFileURL is nil. Cannot save deviceID.")
            return
        }
        do {
            try id.write(to: modernURL, atomically: true, encoding: .utf8)
            debugLog("[DEBUG] deviceID successfully saved to: \(modernURL.path)")
        } catch {
            debugLog("[DEBUG] Error saving deviceID: \(error)")
        }
    }
    
    private func loadDeviceID() -> String? {
        debugLog("[DEBUG] Attempting to load deviceID...")
        ensureAppDirectoryExists()
        // If we cannot resolve the target URL, generate and persist a fresh ID
        // rather than returning nil.
        guard let modernURL = modernFileURL else {
            debugLog("[DEBUG] modernFileURL is nil. Generating new deviceID.")
            let newID = UUID().uuidString
            saveDeviceID(newID)
            return newID
        }
        // 1. Prüfe, ob das neue Format existiert
        if FileManager.default.fileExists(atPath: modernURL.path) {
            debugLog("[DEBUG] Found modern deviceID file at: \(modernURL.path)")
            if let id = try? String(contentsOf: modernURL, encoding: .utf8) {
                debugLog("[DEBUG] Loaded deviceID from modern file: \(id)")
                return id
            } else {
                debugLog("[DEBUG] Failed to read deviceID from modern file. Generating new deviceID.")
                let newID = UUID().uuidString
                saveDeviceID(newID)
                return newID
            }
        }
        // 2. Prüfe, ob das alte Format existiert und migriere ggf.
        if let legacyURL = legacyFileURL,
           FileManager.default.fileExists(atPath: legacyURL.path),
           let data = try? Data(contentsOf: legacyURL),
           let legacyID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) as String? {
            debugLog("[DEBUG] Found legacy deviceID file at: \(legacyURL.path). Migrating to modern format.")
            // Migriere ins neue Format
            saveDeviceID(legacyID)
            return legacyID
        }
        // 3. Nichts gefunden: Neue deviceID erzeugen, speichern und zurückgeben
        debugLog("[DEBUG] No deviceID found. Generating new deviceID.")
        let newID = UUID().uuidString
        saveDeviceID(newID)
        return newID
    }
}
