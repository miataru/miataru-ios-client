/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruRequestExecutor.swift
 * miataru
 *
 * Created by Codex on 04.03.26.
 */

import Foundation

actor MiataruRequestExecutor {
    typealias SleepHandler = (UInt64) async throws -> Void
    typealias JitterProvider = (ClosedRange<Double>) -> Double

    static let shared = MiataruRequestExecutor()

    private let sleepHandler: SleepHandler
    private let jitterProvider: JitterProvider

    init(
        sleepHandler: @escaping SleepHandler = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        jitterProvider: @escaping JitterProvider = { range in
            Double.random(in: range)
        }
    ) {
        self.sleepHandler = sleepHandler
        self.jitterProvider = jitterProvider
    }

    func execute<T>(
        policy: MiataruRetryPolicy,
        operationName: String,
        operation: () async throws -> T
    ) async throws -> T {
        var currentAttempt = 0
        var remainingRetries = max(0, policy.maxRetries)

        while true {
            do {
                return try await operation()
            } catch {
                guard remainingRetries > 0, MiataruRetryClassifier.isRetryable(error) else {
                    throw error
                }

                remainingRetries -= 1
                currentAttempt += 1

                let delay = policy.delaySeconds(
                    forRetryAttempt: currentAttempt,
                    jitterProvider: jitterProvider
                )
                let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
                if nanoseconds > 0 {
                    try await sleepHandler(nanoseconds)
                }

                debugLog("[MiataruRequestExecutor] Retry \(currentAttempt)/\(policy.maxRetries) for \(operationName)")
            }
        }
    }
}
