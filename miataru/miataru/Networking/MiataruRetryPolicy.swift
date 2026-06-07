/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruRetryPolicy.swift
 * miataru
 *
 * Created by Codex on 04.03.26.
 */

import Foundation
import MiataruAPIClient

struct MiataruRetryPolicy {
    let maxRetries: Int
    let baseBackoff: TimeInterval
    let jitterFraction: Double

    static let read = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 0.8, jitterFraction: 0.25)
    static let write = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 1.0, jitterFraction: 0.25)
    static let updateLocation = MiataruRetryPolicy(maxRetries: 1, baseBackoff: 1.2, jitterFraction: 0.25)

    func delaySeconds(forRetryAttempt retryAttempt: Int, jitterProvider: (ClosedRange<Double>) -> Double) -> TimeInterval {
        let safeRetryAttempt = max(1, retryAttempt)
        let exponent = Double(safeRetryAttempt - 1)
        let baseDelay = baseBackoff * pow(2.0, exponent)
        guard jitterFraction > 0 else {
            return max(0, baseDelay)
        }
        let lower = max(0, 1.0 - jitterFraction)
        let upper = max(lower, 1.0 + jitterFraction)
        let jitterMultiplier = jitterProvider(lower...upper)
        return max(0, baseDelay * jitterMultiplier)
    }
}

enum MiataruRetryClassifier {
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed
    ]

    static func isRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? MiataruAPIClient.APIError else {
            return false
        }
        return isRetryable(apiError)
    }

    static func isRetryable(_ error: MiataruAPIClient.APIError) -> Bool {
        switch error {
        case .requestFailed(let underlyingError):
            guard let urlError = findURLError(in: underlyingError) else {
                return false
            }
            return retryableURLErrorCodes.contains(urlError.code)
        case .serverError(let statusCode, _):
            return isRetryableHTTPStatus(statusCode)
        case .invalidResponse(let response):
            if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                if statusCode == 401 || statusCode == 403 {
                    return false
                }
                return true
            }
            return true
        case .decodingError:
            return true
        case .invalidURL, .encodingError:
            return false
        }
    }

    private static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func findURLError(in error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code), userInfo: nsError.userInfo)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return findURLError(in: underlyingError)
        }

        return nil
    }
}
