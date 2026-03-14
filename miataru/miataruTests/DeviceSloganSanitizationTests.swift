/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceSloganSanitizationTests.swift
 * miataruTests
 *
 * Created by Codex on 14.03.26.
 */

import Testing
@testable import miataru

struct DeviceSloganSanitizationTests {
    @Test("Device slogan draft sanitization preserves regular spaces while typing")
    func deviceSloganDraftSanitizationPreservesSpacesWhileTyping() {
        let draft = "Road Trip "
        #expect(MiataruAppAPI.sanitizeDeviceSloganDraft(draft) == draft)
    }

    @Test("Device slogan cleansing trims surrounding whitespace on save")
    func deviceSloganCleansingTrimsSurroundingWhitespaceOnSave() {
        #expect(MiataruAppAPI.cleanseDeviceSlogan("  Road Trip  ") == "Road Trip")
    }
}
