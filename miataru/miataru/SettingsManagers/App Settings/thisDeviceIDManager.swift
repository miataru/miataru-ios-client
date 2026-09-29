/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * thisDeviceIDManager.swift
 * miataru
 */

import Darwin
import Foundation
import UIKit

extension Notification.Name {
    static let thisDeviceIDDidChange = Notification.Name("thisDeviceIDDidChange")
}

struct DeviceIDFileAccess {
    let read: (URL) throws -> Data
    let write: (Data, URL) throws -> Void
    let createDirectory: (URL) throws -> Void

    static let live = DeviceIDFileAccess(
        read: { try Data(contentsOf: $0) },
        write: { data, url in
            // The identity is needed after the first unlock for background location relaunches.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        },
        createDirectory: { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    )
}

class thisDeviceIDManager: @unchecked Sendable {
    static let shared = thisDeviceIDManager()

    private enum StoredIDRead {
        case found(String)
        case missing
        case unavailable
    }

    private let legacyFileName = "deviceID.plist"
    private let modernFileName = "deviceIDmodern.txt"
    private let lock = NSLock()
    private let directoryURLProvider: () -> URL?
    private let fileAccess: DeviceIDFileAccess
    private let protectedDataAvailable: () -> Bool
    private var cachedDeviceID: String?

    private init() {
        directoryURLProvider = {
            guard let appSupportDir = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first, let bundleID = Bundle.main.bundleIdentifier else {
                return nil
            }
            return appSupportDir.appendingPathComponent(bundleID, isDirectory: true)
        }
        fileAccess = .live
        protectedDataAvailable = { UIApplication.shared.isProtectedDataAvailable }
    }

    init(directoryURL: URL,
         fileAccess: DeviceIDFileAccess,
         protectedDataAvailable: @escaping () -> Bool = { true }) {
        directoryURLProvider = { directoryURL }
        self.fileAccess = fileAccess
        self.protectedDataAvailable = protectedDataAvailable
    }

    /// A temporarily unreadable identity is unavailable. It must never be replaced implicitly.
    var deviceIDIfAvailable: String? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedDeviceID { return cachedDeviceID }
        guard let directoryURL = directoryURLProvider() else { return nil }
        do {
            try fileAccess.createDirectory(directoryURL)
        } catch {
            debugLog("[DeviceID] Application Support directory is unavailable: \(error)")
            return nil
        }

        let modernURL = directoryURL.appendingPathComponent(modernFileName)
        switch readModernID(at: modernURL) {
        case .found(let id):
            cachedDeviceID = id
            return id
        case .unavailable:
            return nil
        case .missing:
            break
        }

        let legacyURL = directoryURL.appendingPathComponent(legacyFileName)
        switch readLegacyID(at: legacyURL) {
        case .found(let id):
            // A failed migration must not discard the still-valid legacy identity.
            _ = persist(id, to: modernURL)
            cachedDeviceID = id
            return id
        case .unavailable:
            return nil
        case .missing:
            break
        }

        // A protected file can appear absent before the first unlock. Only create a new
        // identity when protected data is available and the new ID can be persisted.
        guard protectedDataAvailable() else { return nil }
        let newID = UUID().uuidString
        guard persist(newID, to: modernURL) else { return nil }
        cachedDeviceID = newID
        return newID
    }

    /// Compatibility accessor for presentation code. An empty value means storage is unavailable.
    var deviceID: String { deviceIDIfAvailable ?? "" }

    @discardableResult
    func setDeviceID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        lock.lock()
        guard let directoryURL = directoryURLProvider() else {
            lock.unlock()
            return false
        }
        do {
            try fileAccess.createDirectory(directoryURL)
        } catch {
            debugLog("[DeviceID] Cannot prepare identity directory: \(error)")
            lock.unlock()
            return false
        }
        let modernURL = directoryURL.appendingPathComponent(modernFileName)
        guard persist(trimmed, to: modernURL) else {
            lock.unlock()
            return false
        }
        let oldID = cachedDeviceID
        cachedDeviceID = trimmed
        lock.unlock()

        if oldID?.uppercased() != trimmed.uppercased() {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .thisDeviceIDDidChange,
                    object: nil,
                    userInfo: ["oldDeviceID": oldID ?? "", "newDeviceID": trimmed]
                )
            }
        }
        return true
    }

    @discardableResult
    func regenerateDeviceID() -> String? {
        let newID = UUID().uuidString
        return setDeviceID(newID) ? newID : nil
    }

    private func readModernID(at url: URL) -> StoredIDRead {
        do {
            let data = try fileAccess.read(url)
            guard let id = String(data: data, encoding: .utf8),
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .unavailable
            }
            return .found(id)
        } catch {
            return Self.isMissingFile(error) ? .missing : .unavailable
        }
    }

    private func readLegacyID(at url: URL) -> StoredIDRead {
        do {
            let data = try fileAccess.read(url)
            guard let id = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) as String?,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .unavailable
            }
            return .found(id)
        } catch {
            return Self.isMissingFile(error) ? .missing : .unavailable
        }
    }

    private func persist(_ id: String, to url: URL) -> Bool {
        do {
            try fileAccess.write(Data(id.utf8), url)
            return true
        } catch {
            debugLog("[DeviceID] Identity write failed; preserving the previous identity: \(error)")
            return false
        }
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError) ||
            (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }
}
