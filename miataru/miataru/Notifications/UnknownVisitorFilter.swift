/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * UnknownVisitorFilter.swift
 * miataru
 *
 * Created by Codex on 21.05.26.
 */

import Foundation
import MiataruAPIClient

struct UnknownVisitorFilter {
    static func visitors(from visitors: [MiataruVisitor],
                         knownDeviceIDs: Set<String>,
                         ignoredDeviceIDs: Set<String>,
                         ownDeviceID: String? = nil) -> [MiataruVisitor] {
        let normalizedKnownIDs = Set(knownDeviceIDs.map(normalizeDeviceID).filter { !$0.isEmpty })
        let normalizedIgnoredIDs = Set(ignoredDeviceIDs.map(normalizeDeviceID).filter { !$0.isEmpty })
        let normalizedOwnDeviceID = ownDeviceID.map(normalizeDeviceID) ?? ""

        var newestVisitorByDeviceID: [String: MiataruVisitor] = [:]
        for visitor in visitors {
            let normalizedVisitorDeviceID = normalizeDeviceID(visitor.DeviceID)
            guard !normalizedVisitorDeviceID.isEmpty else { continue }
            guard normalizedVisitorDeviceID != normalizedOwnDeviceID else { continue }
            guard !normalizedKnownIDs.contains(normalizedVisitorDeviceID) else { continue }
            guard !normalizedIgnoredIDs.contains(normalizedVisitorDeviceID) else { continue }

            let normalizedVisitor = MiataruVisitor(
                DeviceID: normalizedVisitorDeviceID,
                TimeStamp: visitor.TimeStamp
            )

            if let existing = newestVisitorByDeviceID[normalizedVisitorDeviceID],
               existing.TimeStampDate >= normalizedVisitor.TimeStampDate {
                continue
            }

            newestVisitorByDeviceID[normalizedVisitorDeviceID] = normalizedVisitor
        }

        return newestVisitorByDeviceID.values.sorted { $0.TimeStampDate > $1.TimeStampDate }
    }

    static func deviceIDs(from visitors: [MiataruVisitor],
                          knownDeviceIDs: Set<String>,
                          ignoredDeviceIDs: Set<String>,
                          ownDeviceID: String? = nil) -> [String] {
        Self.visitors(
            from: visitors,
            knownDeviceIDs: knownDeviceIDs,
            ignoredDeviceIDs: ignoredDeviceIDs,
            ownDeviceID: ownDeviceID
        ).map { $0.DeviceID }
    }

    static func normalizeDeviceID(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
