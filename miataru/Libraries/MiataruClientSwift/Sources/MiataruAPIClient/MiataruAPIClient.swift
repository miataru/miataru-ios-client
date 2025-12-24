import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Local Logging Helper

/// Lightweight logging helper for the Miataru client library.
///
/// The main application target defines its own `debugLog` function, but it
/// isn't visible inside this Swift package module. To keep the recent history
/// logging changes compiling while still emitting useful diagnostics during
/// development, we provide a local implementation that simply prints the
/// message in debug builds.
private func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}

/// Configuration part of the Miataru request.
public struct MiataruConfig: Codable {
    let RequestMiataruDeviceID: String
}

/// Strongly typed request body for the GetLocationHistory endpoint.
private struct GetLocationHistoryRequestBody: Encodable {
    var MiataruConfig: MiataruConfig?
    var MiataruGetLocationHistory: GetLocationHistoryPayload

    enum CodingKeys: String, CodingKey {
        case MiataruConfig
        case MiataruGetLocationHistory
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let config = MiataruConfig {
            try container.encode(config, forKey: .MiataruConfig)
        }
        try container.encode(MiataruGetLocationHistory, forKey: .MiataruGetLocationHistory)
    }
}

/// Payload for GetLocation request.
public struct GetLocationPayload: Codable {
    public let Device: String
    public init(Device: String) {
        self.Device = Device
    }
}

/// Payload for the GetLocationHistory request.
public struct GetLocationHistoryPayload: Codable {
    public let Device: String
    public let Amount: String
    public init(Device: String, Amount: String) {
        self.Device = Device
        self.Amount = Amount
    }
}

/// Payload for the UpdateLocation request.
public struct UpdateLocationPayload: Codable {
    public let Device: String
    public var Timestamp: String
    public var Longitude: Double
    public var Latitude: Double
    public var HorizontalAccuracy: Double
    public var Speed: Double?
    public var BatteryLevel: Double?
    /// Altitude above mean sea level in meters
    public var Altitude: Double?

    /// Computed property für den Zugriff als Date
    public var TimestampDate: Date {
        get {
            if let ms = Double(Timestamp) {
                return Date(timeIntervalSince1970: ms)
            } else {
                return Date(timeIntervalSince1970: 0)
            }
        }
        set {
            Timestamp = String(Int64(newValue.timeIntervalSince1970))
        }
    }

    enum CodingKeys: String, CodingKey {
        case Device, Timestamp, Longitude, Latitude, HorizontalAccuracy, Speed, BatteryLevel, Altitude
    }

    public init(Device: String, Timestamp: String, Longitude: Double, Latitude: Double, HorizontalAccuracy: Double, Speed: Double? = nil, BatteryLevel: Double? = nil, Altitude: Double? = nil) {
        self.Device = Device
        self.Timestamp = Timestamp
        self.Longitude = Longitude
        self.Latitude = Latitude
        self.HorizontalAccuracy = HorizontalAccuracy
        self.Speed = Speed
        self.BatteryLevel = BatteryLevel
        self.Altitude = Altitude
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        try container.encode(Timestamp, forKey: .Timestamp)
        try container.encode(String(Longitude), forKey: .Longitude)
        try container.encode(String(Latitude), forKey: .Latitude)
        try container.encode(String(HorizontalAccuracy), forKey: .HorizontalAccuracy)
        if let Speed = Speed { try container.encode(String(Speed), forKey: .Speed) }
        if let BatteryLevel = BatteryLevel { try container.encode(String(BatteryLevel), forKey: .BatteryLevel) }
        if let Altitude = Altitude { try container.encode(String(Altitude), forKey: .Altitude) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Device = try container.decode(String.self, forKey: .Device)
        // Timestamp kann als String oder als Zahl kommen
        if let tsString = try? container.decode(String.self, forKey: .Timestamp) {
            Timestamp = tsString
        } else if let tsInt = try? container.decode(Int64.self, forKey: .Timestamp) {
            Timestamp = String(tsInt)
        } else if let tsDouble = try? container.decode(Double.self, forKey: .Timestamp) {
            Timestamp = String(Int64(tsDouble))
        } else {
            Timestamp = "0"
        }
        // Longitude, Latitude, HorizontalAccuracy können String oder Double sein
        Longitude = try Self.decodeDoubleStringOrNumber(container: container, key: .Longitude)
        Latitude = try Self.decodeDoubleStringOrNumber(container: container, key: .Latitude)
        HorizontalAccuracy = try Self.decodeDoubleStringOrNumber(container: container, key: .HorizontalAccuracy)
        // Optionale Felder
        Speed = try? Self.decodeDoubleStringOrNumber(container: container, key: .Speed)
        BatteryLevel = try? Self.decodeDoubleStringOrNumber(container: container, key: .BatteryLevel)
        Altitude = try? Self.decodeDoubleStringOrNumber(container: container, key: .Altitude)
    }
    
    private static func decodeDoubleStringOrNumber(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            return doubleVal
        } else if let stringVal = try? container.decode(String.self, forKey: key) {
            let normalized = stringVal
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let doubleVal = Double(normalized) {
                return doubleVal
            }
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Konnte Wert nicht als Double dekodieren.")
    }
}

/// Represents the location data received from the server, matching the API specification.
public struct MiataruLocationData: Codable {
    public let Device: String
    public let Timestamp: String
    public var Longitude: Double
    public var Latitude: Double
    public var HorizontalAccuracy: Double
    public var Speed: Double?
    public var BatteryLevel: Double?
    /// Altitude above mean sea level in meters
    public var Altitude: Double?

    /// Computed property für den Zugriff als Date
    public var TimestampDate: Date {
        if let ms = Double(Timestamp) {
            return Date(timeIntervalSince1970: ms)
        } else {
            return Date(timeIntervalSince1970: 0)
        }
    }

    enum CodingKeys: String, CodingKey {
        case Device, Timestamp, Longitude, Latitude, HorizontalAccuracy, Speed, BatteryLevel, Altitude
    }

    public init(Device: String, Timestamp: String, Longitude: Double, Latitude: Double, HorizontalAccuracy: Double, Speed: Double? = nil, BatteryLevel: Double? = nil, Altitude: Double? = nil) {
        self.Device = Device
        self.Timestamp = Timestamp
        self.Longitude = Longitude
        self.Latitude = Latitude
        self.HorizontalAccuracy = HorizontalAccuracy
        self.Speed = Speed
        self.BatteryLevel = BatteryLevel
        self.Altitude = Altitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        Device = try container.decode(String.self, forKey: .Device)
        // Timestamp kann als String oder als Zahl kommen
        if let tsString = try? container.decode(String.self, forKey: .Timestamp) {
            Timestamp = tsString
        } else if let tsInt = try? container.decode(Int64.self, forKey: .Timestamp) {
            Timestamp = String(tsInt)
        } else if let tsDouble = try? container.decode(Double.self, forKey: .Timestamp) {
            Timestamp = String(Int64(tsDouble))
        } else {
            Timestamp = "0"
        }
        // Longitude, Latitude, HorizontalAccuracy können String oder Double sein
        Longitude = try Self.decodeDoubleStringOrNumber(container: container, key: .Longitude)
        Latitude = try Self.decodeDoubleStringOrNumber(container: container, key: .Latitude)
        HorizontalAccuracy = try Self.decodeDoubleStringOrNumber(container: container, key: .HorizontalAccuracy)
        // Optionale Felder
        Speed = try? Self.decodeDoubleStringOrNumber(container: container, key: .Speed)
        BatteryLevel = try? Self.decodeDoubleStringOrNumber(container: container, key: .BatteryLevel)
        Altitude = try? Self.decodeDoubleStringOrNumber(container: container, key: .Altitude)
    }
    
    private static func decodeDoubleStringOrNumber(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let doubleVal = try? container.decode(Double.self, forKey: key) {
            return doubleVal
        } else if let stringVal = try? container.decode(String.self, forKey: key) {
            let normalized = stringVal
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let doubleVal = Double(normalized) {
                return doubleVal
            }
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Konnte Wert nicht als Double dekodieren.")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        try container.encode(Timestamp, forKey: .Timestamp)
        try container.encode(String(Longitude), forKey: .Longitude)
        try container.encode(String(Latitude), forKey: .Latitude)
        try container.encode(String(HorizontalAccuracy), forKey: .HorizontalAccuracy)
        if let Speed = Speed { try container.encode(String(Speed), forKey: .Speed) }
        if let BatteryLevel = BatteryLevel { try container.encode(String(BatteryLevel), forKey: .BatteryLevel) }
        if let Altitude = Altitude { try container.encode(String(Altitude), forKey: .Altitude) }
    }
}

/// The structure of the response for a GetLocation request.
public struct MiataruGetLocationResponse: Codable {
    let MiataruLocation: [MiataruLocationData]

    enum CodingKeys: String, CodingKey {
        case MiataruLocation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Versuche als [MiataruLocationData?] zu decodieren
        let rawLocations = try container.decodeIfPresent([MiataruLocationData?].self, forKey: .MiataruLocation) ?? []
        // Filtere nil heraus
        self.MiataruLocation = rawLocations.compactMap { $0 }
    }
}

/// The structure of the response for a GetLocationHistory request.
public struct MiataruGetLocationHistoryResponse: Codable {
    let MiataruLocation: [MiataruLocationData]
    // We can add MiataruServerConfig here if needed in the future.

    enum CodingKeys: String, CodingKey {
        case MiataruLocation
    }

    public init(MiataruLocation: [MiataruLocationData]) {
        self.MiataruLocation = MiataruLocation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard var locationsContainer = try? container.nestedUnkeyedContainer(forKey: .MiataruLocation) else {
            self.MiataruLocation = []
            return
        }

        var parsedLocations: [MiataruLocationData] = []
        var index = 0

        while !locationsContainer.isAtEnd {
            do {
                let entry = try locationsContainer.decode(MiataruLocationData.self)
                parsedLocations.append(entry)
            } catch {
                debugLog("[MiataruAPIClient] Skipping malformed history entry at index \(index): \(error)")
                _ = try? locationsContainer.decode(SkipDecodable.self)
            }
            index += 1
        }

        self.MiataruLocation = parsedLocations
    }
}

private struct SkipDecodable: Decodable {
    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                _ = try? unkeyed.decode(SkipDecodable.self)
            }
        } else if var keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            for key in keyed.allKeys {
                _ = try? keyed.decode(SkipDecodable.self, forKey: key)
            }
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            _ = try? container.decode(Bool.self)
            _ = try? container.decode(Double.self)
            _ = try? container.decode(String.self)
        }
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

/// The structure of the response for an UpdateLocation request.
public struct MiataruUpdateLocationResponse: Codable {
    let MiataruResponse: String // Expect "ACK"
}

public enum MiataruAPIClient {

    private static let session = URLSession.shared
    private static let jsonDecoder = JSONDecoder()

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Keep the original property declaration order so the Miataru history
        // payload encodes as `{ "Device": ..., "Amount": ... }` instead of
        // being alphabetically sorted. The backend (and accompanying debug
        // tooling) expects the keys in this order.
        return encoder
    }
    
    // MARK: - Public API Methods
    
    /// Fetches the current location for one or more devices.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceIDs: The IDs of the devices to fetch the location for.
    ///   - requestingDeviceID: The ID of the device making the request (optional).
    /// - Returns: An array of location data objects.
    /// - Throws: An `APIError` if the request fails.
    public static func getLocation(serverURL: URL,
                           forDeviceIDs deviceIDs: [String],
                           requestingDeviceID: String?) async throws -> [MiataruLocationData] {
        
        let url = serverURL.appendingPathComponent("v1/GetLocation")
        
        let devicesPayload = deviceIDs.map { ["Device": $0] }
        var jsonPayload: [String: Any] = ["MiataruGetLocation": devicesPayload]
        
        if let reqDeviceID = requestingDeviceID {
            jsonPayload["MiataruConfig"] = ["RequestMiataruDeviceID": reqDeviceID]
        }
        
        let data = try await performPostRequest(url: url, jsonPayload: jsonPayload)
        
        do {
            //print("Data: ",data);
            /*if let jsonString = String(data: data, encoding: .utf8) {
                print("Data als String: \(jsonString)")
            } else {
                print("Konnte Data nicht als UTF-8 String dekodieren.")
            }*/
            let response = try jsonDecoder.decode(MiataruGetLocationResponse.self, from: data)
            return response.MiataruLocation
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    /// Fetches the location history for a specific device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to fetch the history for.
    ///   - requestingDeviceID: The ID of the device making the request (optional).
    ///   - amount: The number of history entries to retrieve.
    /// - Returns: An array of location data objects.
    /// - Throws: An `APIError` if the request fails.
    public static func getLocationHistory(serverURL: URL,
                                  forDeviceID deviceID: String,
                                  requestingDeviceID: String?,
                                  amount: Int) async throws -> [MiataruLocationData] {
        
        let url = serverURL.appendingPathComponent("v1/GetLocationHistory")

        let sanitizedRequestID: String? = {
            guard let value = requestingDeviceID, !value.isEmpty else { return nil }
            return value
        }()

        let requestBody = GetLocationHistoryRequestBody(
            MiataruConfig: sanitizedRequestID.map { MiataruConfig(RequestMiataruDeviceID: $0) },
            MiataruGetLocationHistory: GetLocationHistoryPayload(Device: deviceID, Amount: String(amount))
        )

        let data: Data
        do {
            data = try await performPostRequest(url: url, encodablePayload: requestBody) {
                "[MiataruAPIClient] Requesting history for device \(deviceID) amount=\(amount) payload=\($0)"
            }
        } catch APIError.encodingError(let err) {
            debugLog("[MiataruAPIClient] Encoding history request failed for device \(deviceID): \(err.localizedDescription)")
            throw APIError.encodingError(err)
        }

        do {
            let response = try jsonDecoder.decode(MiataruGetLocationHistoryResponse.self, from: data)
            debugLog("[MiataruAPIClient] Received history entries=\(response.MiataruLocation.count) for device \(deviceID)")
            return response.MiataruLocation
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                debugLog("[MiataruAPIClient] History decode failed for device \(deviceID). Payload=\(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }
    
    /// Updates the location for a single device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - locationData: The location data to be sent to the server.
    ///   - enableHistory: Whether the server should store location history for this device.
    ///   - retentionTime: The time in minutes for the server to retain this location data.
    /// - Returns: A boolean indicating if the server acknowledged the update.
    /// - Throws: An `APIError` if the request fails.
    public static func updateLocation(serverURL: URL,
                              locationData: UpdateLocationPayload,
                              enableHistory: Bool,
                              retentionTime: Int) async throws -> Bool {
                                  
        let url = serverURL.appendingPathComponent("v1/UpdateLocation")

        var locationDict: [String: Any] = [
            "Device": locationData.Device,
            "Timestamp": locationData.Timestamp,
            "Longitude": locationData.Longitude,
            "Latitude": locationData.Latitude,
            "HorizontalAccuracy": locationData.HorizontalAccuracy
        ]
        if let speed = locationData.Speed { locationDict["Speed"] = speed }
        if let battery = locationData.BatteryLevel { locationDict["BatteryLevel"] = battery }
        if let altitude = locationData.Altitude { locationDict["Altitude"] = altitude }

        let jsonPayload: [String: Any] = [
            "MiataruConfig": [
                "EnableLocationHistory": String(enableHistory),
                "LocationDataRetentionTime": String(retentionTime)
            ],
            "MiataruLocation": [locationDict]
        ]
        
        let data = try await performPostRequest(url: url, jsonPayload: jsonPayload)
        
        do {
            let response = try jsonDecoder.decode(MiataruUpdateLocationResponse.self, from: data)
            return response.MiataruResponse == "ACK"
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Private Helper
    
    private static func performPostRequest(url: URL,
                                          jsonPayload: [String: Any],
                                          logMessage: ((String) -> String)? = nil) async throws -> Data {
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonPayload)
            let bodyString = String(data: data, encoding: .utf8)
            return try await performPostRequest(url: url,
                                                httpBody: data,
                                                bodyString: bodyString,
                                                customLog: logMessage)
        } catch {
            debugLog("[MiataruAPIClient] Failed to encode request for URL \(url.absoluteString): \(error.localizedDescription)")
            throw APIError.encodingError(error)
        }
    }

    private static func performPostRequest<T: Encodable>(url: URL,
                                                         encodablePayload: T,
                                                         logMessage: ((String) -> String)? = nil) async throws -> Data {
        do {
            let encoder = makeJSONEncoder()
            let data = try encoder.encode(encodablePayload)
            let bodyString = String(data: data, encoding: .utf8)
            return try await performPostRequest(url: url,
                                                httpBody: data,
                                                bodyString: bodyString,
                                                customLog: logMessage)
        } catch {
            debugLog("[MiataruAPIClient] Failed to encode request for URL \(url.absoluteString): \(error.localizedDescription)")
            throw APIError.encodingError(error)
        }
    }

    private static func performPostRequest(url: URL,
                                          httpBody: Data,
                                          bodyString: String?,
                                          customLog: ((String) -> String)?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = httpBody

        if let bodyString = bodyString {
            if let customLog = customLog {
                debugLog(customLog(bodyString))
            } else {
                debugLog("[MiataruAPIClient] POST \(url.absoluteString) body=\(bodyString)")
            }
        }

        // Eigene async-Bridge für URLSession
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        debugLog("[MiataruAPIClient] Request failed for URL \(url.absoluteString): \(error.localizedDescription)")
                        continuation.resume(throwing: APIError.requestFailed(error))
                        return
                    }
                    guard let data = data, let response = response else {
                        debugLog("[MiataruAPIClient] Request returned without data for URL \(url.absoluteString)")
                        continuation.resume(throwing: APIError.invalidResponse(nil))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                task.resume()
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("[MiataruAPIClient] Non-HTTP response for URL \(url.absoluteString)")
            throw APIError.invalidResponse(response)
        }

        debugLog("[MiataruAPIClient] Response status \(httpResponse.statusCode) for URL \(url.absoluteString)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                debugLog("[MiataruAPIClient] Error response body=\(responseString)")
            }
            throw APIError.invalidResponse(response)
        }
        return data
    }
    
    public enum APIError: Error {
        case invalidURL
        case invalidResponse(URLResponse?)
        case encodingError(Error)
        case decodingError(Error)
        case requestFailed(Error)
    }
} 
