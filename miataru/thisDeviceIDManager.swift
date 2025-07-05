import Foundation

class thisDeviceIDManager {
    private let legacyFileName = "deviceID.plist"
    private let modernFileName = "deviceIDmodern.plist"
    
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
        ensureAppDirectoryExists()
        guard let modernURL = modernFileURL else { return }
        do {
            try id.write(to: modernURL, atomically: true, encoding: .utf8)
        } catch {
            print("Fehler beim Speichern der deviceID: \(error)")
        }
    }
    
    private func loadDeviceID() -> String? {
        ensureAppDirectoryExists()
        guard let modernURL = modernFileURL else { return nil }
        // 1. Prüfe, ob das neue Format existiert
        if FileManager.default.fileExists(atPath: modernURL.path) {
            return try? String(contentsOf: modernURL, encoding: .utf8)
        }
        // 2. Prüfe, ob das alte Format existiert und migriere ggf.
        guard let legacyURL = legacyFileURL else { return nil }
        if FileManager.default.fileExists(atPath: legacyURL.path),
           let legacyID = NSKeyedUnarchiver.unarchiveObject(withFile: legacyURL.path) as? String {
            // Migriere ins neue Format
            saveDeviceID(legacyID)
            return legacyID
        }
        // 3. Nichts gefunden: Neue deviceID erzeugen, speichern und zurückgeben
        let newID = UUID().uuidString
        saveDeviceID(newID)
        return newID
    }
    
    public var deviceID: String? {
        return loadDeviceID()
    }
} 