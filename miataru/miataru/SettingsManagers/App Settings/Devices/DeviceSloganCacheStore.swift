/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceSloganCacheStore.swift
 * miataru
 *
 * Created by Codex on 15.02.26.
 */

import Foundation
import MiataruAPIClient

@MainActor
final class DeviceSloganCacheStore: ObservableObject {
    static let shared = DeviceSloganCacheStore()

    @Published private(set) var slogansByDeviceID: [String: String]
    @Published private(set) var knownDeviceIDs: Set<String>

    private var fetchingDeviceIDs: Set<String> = []
    private var lastFetchByDeviceID: [String: Date]
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let slogansByDeviceID = "device_slogans_by_device_id"
        static let knownDeviceIDs = "device_slogans_known_device_ids"
        static let lastFetchByDeviceID = "device_slogans_last_fetch_by_device_id"
    }

    private init() {
        self.slogansByDeviceID = defaults.dictionary(forKey: Keys.slogansByDeviceID) as? [String: String] ?? [:]
        self.knownDeviceIDs = Set(defaults.stringArray(forKey: Keys.knownDeviceIDs) ?? [])
        if let raw = defaults.dictionary(forKey: Keys.lastFetchByDeviceID) as? [String: TimeInterval] {
            self.lastFetchByDeviceID = raw.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = Date(timeIntervalSince1970: entry.value)
            }
        } else {
            self.lastFetchByDeviceID = [:]
        }
    }

    func slogan(for deviceID: String) -> String? {
        slogansByDeviceID[normalizedDeviceID(deviceID)]
    }

    func isKnown(for deviceID: String) -> Bool {
        knownDeviceIDs.contains(normalizedDeviceID(deviceID))
    }

    func cacheSlogan(_ slogan: String?, for deviceID: String) {
        let normalizedID = normalizedDeviceID(deviceID)
        let normalizedSlogan = normalizedSloganValue(slogan)

        knownDeviceIDs.insert(normalizedID)

        if let normalizedSlogan {
            slogansByDeviceID[normalizedID] = normalizedSlogan
        } else {
            slogansByDeviceID.removeValue(forKey: normalizedID)
        }

        persist()
    }

    @discardableResult
    func fetchSloganIfNeeded(for deviceID: String,
                             serverURL: URL,
                             requestingDeviceID: String,
                             requestingDeviceKey: String) async -> Error? {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return nil }
        guard !isKnown(for: normalizedID) else { return nil }
        guard !fetchingDeviceIDs.contains(normalizedID) else { return nil }

        fetchingDeviceIDs.insert(normalizedID)
        defer { fetchingDeviceIDs.remove(normalizedID) }

        do {
            let slogan = try await MiataruAPIClient.getDeviceSlogan(
                serverURL: serverURL,
                forDeviceID: normalizedID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
            cacheSlogan(slogan.Slogan, for: normalizedID)
            markFetchAttempt(for: normalizedID, at: Date())
            return nil
        } catch {
            markFetchAttempt(for: normalizedID, at: Date())
            debugLog("[DeviceSloganCacheStore] Failed fetching slogan for \(normalizedID): \(error)")
            return error
        }
    }

    @discardableResult
    func refreshSloganIfStale(for deviceID: String,
                              serverURL: URL,
                              requestingDeviceID: String,
                              requestingDeviceKey: String,
                              minimumRefreshInterval: TimeInterval = 300,
                              force: Bool = false) async -> Error? {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return nil }
        guard !fetchingDeviceIDs.contains(normalizedID) else { return nil }

        if !force,
           let lastFetch = lastFetchByDeviceID[normalizedID],
           Date().timeIntervalSince(lastFetch) < minimumRefreshInterval {
            return nil
        }

        fetchingDeviceIDs.insert(normalizedID)
        defer { fetchingDeviceIDs.remove(normalizedID) }

        do {
            let slogan = try await MiataruAPIClient.getDeviceSlogan(
                serverURL: serverURL,
                forDeviceID: normalizedID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
            cacheSlogan(slogan.Slogan, for: normalizedID)
            markFetchAttempt(for: normalizedID, at: Date())
            return nil
        } catch {
            markFetchAttempt(for: normalizedID, at: Date())
            debugLog("[DeviceSloganCacheStore] Failed refreshing slogan for \(normalizedID): \(error)")
            return error
        }
    }

    func markFreshNow(for deviceID: String) {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return }
        markFetchAttempt(for: normalizedID, at: Date())
    }

    private func persist() {
        defaults.set(slogansByDeviceID, forKey: Keys.slogansByDeviceID)
        defaults.set(Array(knownDeviceIDs).sorted(), forKey: Keys.knownDeviceIDs)
        let serializedLastFetch = lastFetchByDeviceID.reduce(into: [String: TimeInterval]()) { partialResult, entry in
            partialResult[entry.key] = entry.value.timeIntervalSince1970
        }
        defaults.set(serializedLastFetch, forKey: Keys.lastFetchByDeviceID)
    }

    private func markFetchAttempt(for deviceID: String, at date: Date) {
        lastFetchByDeviceID[deviceID] = date
        persist()
    }

    private func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func normalizedSloganValue(_ slogan: String?) -> String? {
        guard let slogan else { return nil }
        let trimmed = slogan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }
}
