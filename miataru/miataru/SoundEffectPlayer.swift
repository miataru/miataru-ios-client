/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * SoundEffectPlayer.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-30.
 */

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

final class SoundEffectPlayer {
    static let shared = SoundEffectPlayer()

#if canImport(AVFoundation)
    private var players: [String: AVAudioPlayer] = [:]
    private var hasConfiguredSession = false
#endif

    private init() {}

    func play(named name: String, fileExtension: String) {
#if canImport(AVFoundation)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            let key = "\(name).\(fileExtension)"
            if let player = self.player(for: key, name: name, fileExtension: fileExtension) {
                player.currentTime = 0
                player.play()
            }
        }
#endif
    }

    /// Plays an iOS system sound (e.g. Tink 1103, Tock 1104). Respects the device silent switch.
    /// Use for lightweight feedback when custom assets are not available.
    func playSystemSound(_ systemSoundID: SystemSoundID) {
#if canImport(AudioToolbox)
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(systemSoundID)
        }
#endif
    }

    /// Returns true if a sound resource with the given name and extension exists in the bundle (same search paths as `play(named:fileExtension:)`).
    func hasResource(named name: String, fileExtension: String) -> Bool {
        soundResourceURL(for: name, fileExtension: fileExtension) != nil
    }

    private func soundResourceURL(for name: String, fileExtension: String) -> URL? {
        let subdirectories: [String?] = [nil, "sounds", "Assets/sounds"]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory) {
                return url
            }
        }
        let pathCandidates = ["sounds/\(name)", "Assets/sounds/\(name)"]
        for path in pathCandidates {
            if let url = Bundle.main.url(forResource: path, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }

#if canImport(AVFoundation)
    private func configureSessionIfNeeded() {
        guard !hasConfiguredSession else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            hasConfiguredSession = true
        } catch {
            debugLog("[SoundEffectPlayer] Failed to configure audio session: \(error)")
        }
    }

    private func player(for key: String, name: String, fileExtension: String) -> AVAudioPlayer? {
        if let cached = players[key] {
            return cached
        }
        guard let url = soundResourceURL(for: name, fileExtension: fileExtension) else {
            debugLog("[SoundEffectPlayer] Missing sound resource: \(name).\(fileExtension)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[key] = player
            return player
        } catch {
            debugLog("[SoundEffectPlayer] Failed to load sound \(name).\(fileExtension): \(error)")
            return nil
        }
    }

#endif
}
