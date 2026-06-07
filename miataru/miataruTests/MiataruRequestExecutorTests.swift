/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruRequestExecutorTests.swift
 * miataruTests
 *
 * Created by Codex on 04.03.26.
 */

import Testing
import Foundation
import MiataruAPIClient
@testable import miataru

struct MiataruRequestExecutorTests {
    @Test("Retries once for transient network error and succeeds")
    func retriesOnceForTransientError() async throws {
        var recordedSleeps: [UInt64] = []
        let executor = MiataruRequestExecutor(
            sleepHandler: { nanoseconds in
                recordedSleeps.append(nanoseconds)
            },
            jitterProvider: { _ in 1.0 }
        )
        let policy = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 0.8, jitterFraction: 0)

        var attemptCount = 0
        let value = try await executor.execute(policy: policy, operationName: "testRead") {
            attemptCount += 1
            if attemptCount == 1 {
                throw MiataruAPIClient.APIError.requestFailed(URLError(.timedOut))
            }
            return "ok"
        }

        #expect(value == "ok")
        #expect(attemptCount == 2)
        #expect(recordedSleeps.count == 1)
        #expect(recordedSleeps.first == 800_000_000)
    }

    @Test("Does not retry for non-retryable auth error")
    func doesNotRetryForAuthError() async throws {
        let executor = MiataruRequestExecutor(
            sleepHandler: { _ in },
            jitterProvider: { _ in 1.0 }
        )
        let policy = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 0.8, jitterFraction: 0)

        var attemptCount = 0
        do {
            _ = try await executor.execute(policy: policy, operationName: "testWrite") {
                attemptCount += 1
                throw MiataruAPIClient.APIError.serverError(statusCode: 401, message: "unauthorized")
            } as String
            Issue.record("Expected request to throw")
        } catch let error as MiataruAPIClient.APIError {
            switch error {
            case .serverError(let statusCode, _):
                #expect(statusCode == 401)
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-API error: \(error)")
        }

        #expect(attemptCount == 1)
    }

    @Test("Classifier marks transient statuses and URL errors as retryable")
    func classifierRecognizesRetryableCases() async throws {
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.serverError(statusCode: 408, message: "timeout")) == true)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.serverError(statusCode: 429, message: "rate")) == true)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.serverError(statusCode: 503, message: "unavailable")) == true)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.requestFailed(URLError(.networkConnectionLost))) == true)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.serverError(statusCode: 403, message: "forbidden")) == false)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.invalidResponse(nil)) == true)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.invalidResponse(HTTPURLResponse(
            url: URL(string: "https://example.org")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        ))) == false)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.invalidURL) == false)
        #expect(MiataruRetryClassifier.isRetryable(MiataruAPIClient.APIError.decodingError(NSError(domain: "test", code: 1))) == true)
    }

    @Test("Retries are exhausted and final error is thrown")
    func retriesAreExhausted() async throws {
        let executor = MiataruRequestExecutor(
            sleepHandler: { _ in },
            jitterProvider: { _ in 1.0 }
        )
        let policy = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 0.8, jitterFraction: 0)
        var attemptCount = 0

        do {
            _ = try await executor.execute(policy: policy, operationName: "testRetryExhaustion") {
                attemptCount += 1
                throw MiataruAPIClient.APIError.requestFailed(URLError(.cannotConnectToHost))
            } as Bool
            Issue.record("Expected request to throw")
        } catch let error as MiataruAPIClient.APIError {
            switch error {
            case .requestFailed(let underlying):
                let urlError = underlying as? URLError
                #expect(urlError?.code == .cannotConnectToHost)
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-API error: \(error)")
        }

        #expect(attemptCount == 2)
    }
}
