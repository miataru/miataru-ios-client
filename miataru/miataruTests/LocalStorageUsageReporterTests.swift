/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocalStorageUsageReporterTests.swift
 * miataruTests
 *
 * Created by Codex on 13.06.26.
 */

import Foundation
import Testing
@testable import miataru

@Suite("Local storage usage reporter")
struct LocalStorageUsageReporterTests {
    @Test("File size reports missing files as zero and existing files by attributes")
    func fileSizeReportsMissingAndExistingFiles() throws {
        let directory = try temporaryDirectory()
        let missingURL = directory.appendingPathComponent("missing.json")
        let fileURL = directory.appendingPathComponent("store.json")

        #expect(LocalStorageUsageReporter.fileSize(at: missingURL) == 0)

        try Data(repeating: 0x7A, count: 321).write(to: fileURL)

        #expect(LocalStorageUsageReporter.fileSize(at: fileURL) == 321)
    }

    @Test("Directory size totals only matching widget snapshot files")
    func directorySizeTotalsOnlyMatchingWidgetSnapshotFiles() throws {
        let directory = try temporaryDirectory()
        try Data(repeating: 0x01, count: 100).write(to: directory.appendingPathComponent("MapSnapshot-one.png"))
        try Data(repeating: 0x02, count: 150).write(to: directory.appendingPathComponent("WidgetMapSnapshot-two.png"))
        try Data(repeating: 0x03, count: 200).write(to: directory.appendingPathComponent("MapSnapshot-three.jpg"))
        try Data(repeating: 0x04, count: 250).write(to: directory.appendingPathComponent("Other.png"))

        let result = LocalStorageUsageReporter.directorySize(at: directory) { url in
            let name = url.lastPathComponent
            return url.pathExtension == "png"
                && (name.hasPrefix("MapSnapshot-") || name.hasPrefix("WidgetMapSnapshot-"))
        }

        #expect(result.bytes == 250)
        #expect(result.count == 2)
    }

    @Test("Byte formatting is compact and non-empty for zero bytes and larger totals")
    func byteFormattingIsCompactAndNonEmpty() {
        #expect(!LocalStorageUsageReporter.byteCountText(0).isEmpty)
        #expect(LocalStorageUsageReporter.byteCountText(512).contains("512"))
        #expect(!LocalStorageUsageReporter.byteCountText(2_500_000).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStorageUsageReporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
