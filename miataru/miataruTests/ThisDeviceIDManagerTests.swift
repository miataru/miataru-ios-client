/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * ThisDeviceIDManagerTests.swift
 * miataruTests
 */

import Foundation
import Testing
@testable import miataru

struct ThisDeviceIDManagerTests {
    @Test("An unreadable existing identity is preserved and retried")
    func existingIdentityReadFailureDoesNotReplaceIt() {
        let files = StubDeviceIDFiles()
        files.files[files.modernURL.path] = Data("existing-device".utf8)
        files.unreadablePaths.insert(files.modernURL.path)
        let manager = files.manager()

        #expect(manager.deviceIDIfAvailable == nil)
        #expect(manager.deviceID.isEmpty)
        #expect(files.writeCount == 0)
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == "existing-device")

        files.unreadablePaths.remove(files.modernURL.path)
        #expect(manager.deviceIDIfAvailable == "existing-device")
        #expect(files.writeCount == 0)
    }

    @Test("An apparently absent identity is not recreated before protected data is available")
    func protectedDataUnavailabilityDefersFirstIdentityCreation() {
        let files = StubDeviceIDFiles()
        files.protectedDataAvailable = false
        let manager = files.manager()

        #expect(manager.deviceIDIfAvailable == nil)
        #expect(files.files.isEmpty)

        files.protectedDataAvailable = true
        let id = manager.deviceIDIfAvailable
        #expect(id != nil)
        #expect(!id!.isEmpty)
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == id)
        #expect(manager.deviceIDIfAvailable == id)
        #expect(files.writeCount == 1)
    }

    @Test("A failed initial write cannot create an ephemeral identity")
    func firstIdentityWriteFailureIsRetried() {
        let files = StubDeviceIDFiles()
        files.failWrites = true
        let manager = files.manager()

        #expect(manager.deviceIDIfAvailable == nil)
        #expect(files.files.isEmpty)

        files.failWrites = false
        let id = manager.deviceIDIfAvailable
        #expect(id != nil)
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == id)
        #expect(files.writeCount == 1)
    }

    @Test("An unreadable legacy identity is preserved instead of replaced")
    func legacyReadFailureDoesNotCreateModernIdentity() throws {
        let files = StubDeviceIDFiles()
        files.files[files.legacyURL.path] = try NSKeyedArchiver.archivedData(
            withRootObject: "legacy-device" as NSString,
            requiringSecureCoding: true
        )
        files.unreadablePaths.insert(files.legacyURL.path)
        let manager = files.manager()

        #expect(manager.deviceIDIfAvailable == nil)
        #expect(files.files[files.modernURL.path] == nil)

        files.unreadablePaths.remove(files.legacyURL.path)
        #expect(manager.deviceIDIfAvailable == "legacy-device")
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == "legacy-device")
    }

    @Test("A failed explicit identity change keeps the old cached and persisted ID")
    func failedSetKeepsOldIdentity() {
        let files = StubDeviceIDFiles()
        files.files[files.modernURL.path] = Data("existing-device".utf8)
        let manager = files.manager()
        #expect(manager.deviceIDIfAvailable == "existing-device")

        files.failWrites = true
        #expect(!manager.setDeviceID("replacement-device"))
        #expect(manager.deviceIDIfAvailable == "existing-device")
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == "existing-device")

        files.failWrites = false
        #expect(manager.setDeviceID("replacement-device"))
        #expect(manager.deviceIDIfAvailable == "replacement-device")
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == "replacement-device")
    }

    @Test("Concurrent first reads create one durable identity")
    func concurrentFirstReadsShareOnePersistedIdentity() {
        let files = StubDeviceIDFiles()
        let manager = files.manager()
        let results = SynchronizedDeviceIDResults()

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            results.append(manager.deviceID)
        }

        let captured = results.values
        #expect(captured.count == 32)
        #expect(Set(captured).count == 1)
        #expect(!captured[0].isEmpty)
        #expect(files.writeCount == 1)
        #expect(String(data: files.files[files.modernURL.path]!, encoding: .utf8) == captured[0])
    }
}

private final class SynchronizedDeviceIDResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class StubDeviceIDFiles {
    let directoryURL = URL(fileURLWithPath: "/device-id-test-\(UUID().uuidString)", isDirectory: true)
    var files: [String: Data] = [:]
    var unreadablePaths: Set<String> = []
    var failWrites = false
    var protectedDataAvailable = true
    var writeCount = 0

    var modernURL: URL { directoryURL.appendingPathComponent("deviceIDmodern.txt") }
    var legacyURL: URL { directoryURL.appendingPathComponent("deviceID.plist") }

    func manager() -> thisDeviceIDManager {
        thisDeviceIDManager(
            directoryURL: directoryURL,
            fileAccess: DeviceIDFileAccess(
                read: { [self] url in
                    if unreadablePaths.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
                    guard let data = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
                    return data
                },
                write: { [self] data, url in
                    if failWrites { throw CocoaError(.fileWriteNoPermission) }
                    files[url.path] = data
                    writeCount += 1
                },
                createDirectory: { _ in }
            ),
            protectedDataAvailable: { [self] in protectedDataAvailable }
        )
    }
}
