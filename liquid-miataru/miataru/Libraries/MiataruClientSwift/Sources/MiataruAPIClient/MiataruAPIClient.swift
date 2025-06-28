import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Defines the structure for a Miataru server request.
public struct MiataruRequest<T: Codable>: Codable {
    let MiataruConfig: MiataruConfig
    let payload: T
    
    // Custom coding keys to match the expected JSON structure.
    enum CodingKeys: String, CodingKey {
        case MiataruConfig
        // The payload key is dynamic based on the type of request.
        // This will be handled by the specific payload type's CodingKeys.
        // We will merge the payload directly into the top-level object during encoding.
        case payload
    }
    
    // Since the payload's key is dynamic, we need custom encoding.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MiataruConfig, forKey: .MiataruConfig)
        
        // This is a simplified assumption. The actual key for the payload
        // (e.g., "MiataruGetLocationHistory") needs to be part of the payload's encoding itself.
        // A more robust implementation is needed here.
        try payload.encode(to: encoder)
    }
}

/// Configuration part of the Miataru request.
public struct MiataruConfig: Codable {
    let RequestMiataruDeviceID: String
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
        case Device, Timestamp, Longitude, Latitude, HorizontalAccuracy
    }

    public init(Device: String, Timestamp: String, Longitude: Double, Latitude: Double, HorizontalAccuracy: Double) {
        self.Device = Device
        self.Timestamp = Timestamp
        self.Longitude = Longitude
        self.Latitude = Latitude
        self.HorizontalAccuracy = HorizontalAccuracy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        try container.encode(Timestamp, forKey: .Timestamp)
        try container.encode(String(Longitude), forKey: .Longitude)
        try container.encode(String(Latitude), forKey: .Latitude)
        try container.encode(String(HorizontalAccuracy), forKey: .HorizontalAccuracy)
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
        let longitudeStr = try container.decode(String.self, forKey: .Longitude)
        let latitudeStr = try container.decode(String.self, forKey: .Latitude)
        let accuracyStr = try container.decode(String.self, forKey: .HorizontalAccuracy)
        guard let longitude = Double(longitudeStr), let latitude = Double(latitudeStr), let accuracy = Double(accuracyStr) else {
            throw DecodingError.dataCorruptedError(forKey: .Longitude, in: container, debugDescription: "Longitude, Latitude oder HorizontalAccuracy konnte nicht in Double umgewandelt werden.")
        }
        Longitude = longitude
        Latitude = latitude
        HorizontalAccuracy = accuracy
    }
}

/// Represents the location data received from the server, matching the API specification.
public struct MiataruLocationData: Codable {
    public let Device: String
    public let Timestamp: String
    public var Longitude: Double
    public var Latitude: Double
    public var HorizontalAccuracy: Double

    /// Computed property für den Zugriff als Date
    public var TimestampDate: Date {
        if let ms = Double(Timestamp) {
            return Date(timeIntervalSince1970: ms)
        } else {
            return Date(timeIntervalSince1970: 0)
        }
    }

    enum CodingKeys: String, CodingKey {
        case Device, Timestamp, Longitude, Latitude, HorizontalAccuracy
    }

    public init(Device: String, Timestamp: String, Longitude: Double, Latitude: Double, HorizontalAccuracy: Double) {
        self.Device = Device
        self.Timestamp = Timestamp
        self.Longitude = Longitude
        self.Latitude = Latitude
        self.HorizontalAccuracy = HorizontalAccuracy
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
        let longitudeStr = try container.decode(String.self, forKey: .Longitude)
        let latitudeStr = try container.decode(String.self, forKey: .Latitude)
        let accuracyStr = try container.decode(String.self, forKey: .HorizontalAccuracy)
        guard let longitude = Double(longitudeStr), let latitude = Double(latitudeStr), let accuracy = Double(accuracyStr) else {
            throw DecodingError.dataCorruptedError(forKey: .Longitude, in: container, debugDescription: "Longitude, Latitude oder HorizontalAccuracy konnte nicht in Double umgewandelt werden.")
        }
        Longitude = longitude
        Latitude = latitude
        HorizontalAccuracy = accuracy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        try container.encode(Timestamp, forKey: .Timestamp)
        try container.encode(String(Longitude), forKey: .Longitude)
        try container.encode(String(Latitude), forKey: .Latitude)
        try container.encode(String(HorizontalAccuracy), forKey: .HorizontalAccuracy)
    }
}

/// The structure of the response for a GetLocation request.
public struct MiataruGetLocationResponse: Codable {
    let MiataruLocation: [MiataruLocationData]
}

/// The structure of the response for a GetLocationHistory request.
public struct MiataruGetLocationHistoryResponse: Codable {
    let MiataruLocation: [MiataruLocationData]
    // We can add MiataruServerConfig here if needed in the future.
}

/// The structure of the response for an UpdateLocation request.
public struct MiataruUpdateLocationResponse: Codable {
    let MiataruResponse: String // Expect "ACK"
}

public enum MiataruAPIClient {
    
    private static let session = URLSession.shared
    private static let jsonDecoder = JSONDecoder()
    
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
        
        var jsonPayload: [String: Any] = [
            "MiataruGetLocationHistory": [
                "Device": deviceID,
                "Amount": String(amount)
            ]
        ]

        if let reqDeviceID = requestingDeviceID {
            jsonPayload["MiataruConfig"] = ["RequestMiataruDeviceID": reqDeviceID]
        }
        
        let data = try await performPostRequest(url: url, jsonPayload: jsonPayload)
        
        do {
            let response = try jsonDecoder.decode(MiataruGetLocationHistoryResponse.self, from: data)
            return response.MiataruLocation
        } catch {
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

        let jsonPayload: [String: Any] = [
            "MiataruConfig": [
                "EnableLocationHistory": String(enableHistory),
                "LocationDataRetentionTime": String(retentionTime)
            ],
            "MiataruLocation": [
                [
                    "Device": locationData.Device,
                    "Timestamp": locationData.Timestamp,
                    "Longitude": locationData.Longitude,
                    "Latitude": locationData.Latitude,
                    "HorizontalAccuracy": locationData.HorizontalAccuracy
                ]
            ]
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
                                          jsonPayload: [String: Any]) async throws -> Data {
        var request: URLRequest
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonPayload)
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = data
        } catch {
            throw APIError.encodingError(error)
        }
        
        // Eigene async-Bridge für URLSession
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: APIError.requestFailed(error))
                        return
                    }
                    guard let data = data, let response = response else {
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
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
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
