/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruNotificationSounds.swift
 * miataru
 *
 * Created by Codex on 07.06.26.
 */

import UserNotifications

enum MiataruNotificationSounds {
    static let smartFrequentActivated = named("confirm.caf")
    static let smartFrequentDeactivated = named("cancel.caf")
    static let unknownVisitor = named("confirm.caf")

    private static func named(_ fileName: String) -> UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(fileName))
    }
}
