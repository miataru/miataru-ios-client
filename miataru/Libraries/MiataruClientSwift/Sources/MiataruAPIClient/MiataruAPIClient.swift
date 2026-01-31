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

/// Strongly typed request body for the GetVisitorHistory endpoint.
private struct GetVisitorHistoryRequestBody: Encodable {
    var MiataruGetVisitorHistory: GetVisitorHistoryPayload

    enum CodingKeys: String, CodingKey {
        case MiataruGetVisitorHistory
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MiataruGetVisitorHistory, forKey: .MiataruGetVisitorHistory)
    }
}

/// Strongly typed request body for the DeleteLocation endpoint.
private struct DeleteLocationRequestBody: Encodable {
    var MiataruDeleteLocation: DeleteLocationPayload

    enum CodingKeys: String, CodingKey {
        case MiataruDeleteLocation
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MiataruDeleteLocation, forKey: .MiataruDeleteLocation)
    }
}

/// Strongly typed request body for the SetDeviceKey endpoint.
private struct SetDeviceKeyRequestBody: Encodable {
    var MiataruSetDeviceKey: SetDeviceKeyPayload

    enum CodingKeys: String, CodingKey {
        case MiataruSetDeviceKey
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MiataruSetDeviceKey, forKey: .MiataruSetDeviceKey)
    }
}

/// Strongly typed request body for the SetAllowedDeviceList endpoint.
private struct SetAllowedDeviceListRequestBody: Encodable {
    var MiataruSetAllowedDeviceList: SetAllowedDeviceListPayload

    enum CodingKeys: String, CodingKey {
        case MiataruSetAllowedDeviceList
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MiataruSetAllowedDeviceList, forKey: .MiataruSetAllowedDeviceList)
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

/// Payload for the DeleteLocation request.
public struct DeleteLocationPayload: Codable {
    public let Device: String
    public let DeviceKey: String?

    public init(Device: String, DeviceKey: String? = nil) {
        self.Device = Device
        self.DeviceKey = DeviceKey
    }

    enum CodingKeys: String, CodingKey {
        case Device
        case DeviceKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        if let DeviceKey = DeviceKey, !DeviceKey.isEmpty {
            try container.encode(DeviceKey, forKey: .DeviceKey)
        }
    }
}

/// Payload for the SetDeviceKey request.
public struct SetDeviceKeyPayload: Codable {
    public let DeviceID: String
    public let CurrentDeviceKey: String?
    public let NewDeviceKey: String

    public init(DeviceID: String, CurrentDeviceKey: String? = nil, NewDeviceKey: String) {
        self.DeviceID = DeviceID
        self.CurrentDeviceKey = CurrentDeviceKey
        self.NewDeviceKey = NewDeviceKey
    }

    enum CodingKeys: String, CodingKey {
        case DeviceID
        case CurrentDeviceKey
        case NewDeviceKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DeviceID, forKey: .DeviceID)
        if let CurrentDeviceKey = CurrentDeviceKey, !CurrentDeviceKey.isEmpty {
            try container.encode(CurrentDeviceKey, forKey: .CurrentDeviceKey)
        }
        try container.encode(NewDeviceKey, forKey: .NewDeviceKey)
    }
}

/// Payload for the SetAllowedDeviceList request.
public struct SetAllowedDeviceListPayload: Codable {
    public let DeviceID: String
    public let DeviceKey: String
    public let allowedDevices: [MiataruAllowedDevice]

    public init(DeviceID: String, DeviceKey: String, allowedDevices: [MiataruAllowedDevice]) {
        self.DeviceID = DeviceID
        self.DeviceKey = DeviceKey
        self.allowedDevices = allowedDevices
    }
}

/// Payload for the GetVisitorHistory request.
public struct GetVisitorHistoryPayload: Codable {
    public let Device: String
    public let Amount: String
    public let DeviceKey: String?

    public init(Device: String, Amount: String, DeviceKey: String? = nil) {
        self.Device = Device
        self.Amount = Amount
        self.DeviceKey = DeviceKey
    }

    enum CodingKeys: String, CodingKey {
        case Device
        case Amount
        case DeviceKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Device, forKey: .Device)
        try container.encode(Amount, forKey: .Amount)
        if let DeviceKey = DeviceKey, !DeviceKey.isEmpty {
            try container.encode(DeviceKey, forKey: .DeviceKey)
        }
    }
}

/// Payload for the UpdateLocation request.
public struct UpdateLocationPayload: Codable {
    public let Device: String
    public let DeviceKey: String?
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
        case Device, DeviceKey, Timestamp, Longitude, Latitude, HorizontalAccuracy, Speed, BatteryLevel, Altitude
    }

    public init(Device: String, DeviceKey: String? = nil, Timestamp: String, Longitude: Double, Latitude: Double, HorizontalAccuracy: Double, Speed: Double? = nil, BatteryLevel: Double? = nil, Altitude: Double? = nil) {
        self.Device = Device
        self.DeviceKey = DeviceKey
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
        if let DeviceKey = DeviceKey, !DeviceKey.isEmpty {
            try container.encode(DeviceKey, forKey: .DeviceKey)
        }
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
        DeviceKey = try? container.decode(String.self, forKey: .DeviceKey)
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

/// Represents a visitor entry from the GetVisitorHistory response.
public struct MiataruVisitor: Codable {
    public let DeviceID: String
    public let TimeStamp: String

    /// Computed property for accessing the timestamp as a Date.
    /// The timestamp from the API is in milliseconds, so we divide by 1000.
    public var TimeStampDate: Date {
        if let ts = Double(TimeStamp) {
            // Timestamps from the API are in milliseconds, convert to seconds
            return Date(timeIntervalSince1970: ts / 1000.0)
        } else {
            return Date(timeIntervalSince1970: 0)
        }
    }
    
    /// Unique identifier combining DeviceID and TimeStamp for use in ForEach
    public var uniqueID: String {
        return "\(DeviceID)-\(TimeStamp)"
    }

    enum CodingKeys: String, CodingKey {
        case DeviceID
        case TimeStamp
    }

    public init(DeviceID: String, TimeStamp: String) {
        self.DeviceID = DeviceID
        self.TimeStamp = TimeStamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        DeviceID = try container.decode(String.self, forKey: .DeviceID)
        // TimeStamp can come as String or number
        if let tsString = try? container.decode(String.self, forKey: .TimeStamp) {
            TimeStamp = tsString
        } else if let tsInt = try? container.decode(Int64.self, forKey: .TimeStamp) {
            TimeStamp = String(tsInt)
        } else if let tsDouble = try? container.decode(Double.self, forKey: .TimeStamp) {
            TimeStamp = String(Int64(tsDouble))
        } else {
            TimeStamp = "0"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DeviceID, forKey: .DeviceID)
        try container.encode(TimeStamp, forKey: .TimeStamp)
    }
}

/// Server configuration information from GetVisitorHistory response.
public struct MiataruVisitorHistoryServerConfig: Codable {
    public let MaximumNumberOfVisitorHistory: String
    public let AvailableVisitorHistory: String

    enum CodingKeys: String, CodingKey {
        case MaximumNumberOfVisitorHistory
        case AvailableVisitorHistory
    }

    public init(MaximumNumberOfVisitorHistory: String, AvailableVisitorHistory: String) {
        self.MaximumNumberOfVisitorHistory = MaximumNumberOfVisitorHistory
        self.AvailableVisitorHistory = AvailableVisitorHistory
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // MaximumNumberOfVisitorHistory can come as String or number
        if let maxString = try? container.decode(String.self, forKey: .MaximumNumberOfVisitorHistory) {
            MaximumNumberOfVisitorHistory = maxString
        } else if let maxInt = try? container.decode(Int.self, forKey: .MaximumNumberOfVisitorHistory) {
            MaximumNumberOfVisitorHistory = String(maxInt)
        } else if let maxDouble = try? container.decode(Double.self, forKey: .MaximumNumberOfVisitorHistory) {
            MaximumNumberOfVisitorHistory = String(Int(maxDouble))
        } else {
            MaximumNumberOfVisitorHistory = "0"
        }
        
        // AvailableVisitorHistory can come as String or number
        if let availString = try? container.decode(String.self, forKey: .AvailableVisitorHistory) {
            AvailableVisitorHistory = availString
        } else if let availInt = try? container.decode(Int.self, forKey: .AvailableVisitorHistory) {
            AvailableVisitorHistory = String(availInt)
        } else if let availDouble = try? container.decode(Double.self, forKey: .AvailableVisitorHistory) {
            AvailableVisitorHistory = String(Int(availDouble))
        } else {
            AvailableVisitorHistory = "0"
        }
    }
}

/// The structure of the response for a GetVisitorHistory request.
public struct MiataruGetVisitorHistoryResponse: Codable {
    public let MiataruServerConfig: MiataruVisitorHistoryServerConfig
    public let MiataruVisitors: [MiataruVisitor]

    enum CodingKeys: String, CodingKey {
        case MiataruServerConfig
        case MiataruVisitors
    }

    public init(MiataruServerConfig: MiataruVisitorHistoryServerConfig, MiataruVisitors: [MiataruVisitor]) {
        self.MiataruServerConfig = MiataruServerConfig
        self.MiataruVisitors = MiataruVisitors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode server config
        MiataruServerConfig = try container.decode(MiataruVisitorHistoryServerConfig.self, forKey: .MiataruServerConfig)

        // Decode visitors array with graceful handling of malformed entries
        guard var visitorsContainer = try? container.nestedUnkeyedContainer(forKey: .MiataruVisitors) else {
            MiataruVisitors = []
            return
        }

        var parsedVisitors: [MiataruVisitor] = []
        var index = 0

        while !visitorsContainer.isAtEnd {
            do {
                let entry = try visitorsContainer.decode(MiataruVisitor.self)
                parsedVisitors.append(entry)
            } catch {
                debugLog("[MiataruAPIClient] Skipping malformed visitor entry at index \(index): \(error)")
                _ = try? visitorsContainer.decode(SkipDecodable.self)
            }
            index += 1
        }

        self.MiataruVisitors = parsedVisitors
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

public struct MiataruDeleteLocationResponse: Codable {
    let MiataruResponse: String
    let MiataruVerboseResponse: String
    let MiataruDeletedCount: Int?
}

public struct MiataruSetDeviceKeyResponse: Codable {
    let MiataruResponse: String
    let MiataruVerboseResponse: String
}

public struct MiataruSetAllowedDeviceListResponse: Codable {
    let MiataruResponse: String
    let MiataruVerboseResponse: String
}

public struct MiataruAllowedDevice: Codable {
    public let DeviceID: String
    public let hasCurrentLocationAccess: Bool
    public let hasHistoryAccess: Bool

    public init(DeviceID: String, hasCurrentLocationAccess: Bool, hasHistoryAccess: Bool) {
        self.DeviceID = DeviceID
        self.hasCurrentLocationAccess = hasCurrentLocationAccess
        self.hasHistoryAccess = hasHistoryAccess
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

public enum MiataruAPIClient {

    public static let packageVersion = "1.1.0"

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
    ///   - requestingDeviceID: The ID of the device making the request.
    /// - Returns: An array of location data objects.
    /// - Throws: An `APIError` if the request fails.
    public static func getLocation(serverURL: URL,
                           forDeviceIDs deviceIDs: [String],
                           requestingDeviceID: String) async throws -> [MiataruLocationData] {
        
        let url = serverURL.appendingPathComponent("v1/GetLocation")
        
        let devicesPayload = deviceIDs.map { ["Device": $0] }
        let jsonPayload: [String: Any] = [
            "MiataruGetLocation": devicesPayload,
            "MiataruConfig": ["RequestMiataruDeviceID": requestingDeviceID]
        ]
        
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
    ///   - requestingDeviceID: The ID of the device making the request.
    ///   - amount: The number of history entries to retrieve.
    /// - Returns: An array of location data objects.
    /// - Throws: An `APIError` if the request fails.
    public static func getLocationHistory(serverURL: URL,
                                  forDeviceID deviceID: String,
                                  requestingDeviceID: String,
                                  amount: Int) async throws -> [MiataruLocationData] {
        
        let url = serverURL.appendingPathComponent("v1/GetLocationHistory")

        let requestBody = GetLocationHistoryRequestBody(
            MiataruConfig: MiataruConfig(RequestMiataruDeviceID: requestingDeviceID),
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
    
    /// Fetches the visitor history for a specific device.
    ///
    /// Visitor history contains a list of devices that have requested the location
    /// of the specified device. This information is stored on the server with every
    /// request to the location or location history information of a device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to fetch the visitor history for.
    ///   - deviceKey: The optional DeviceKey for authentication.
    ///   - amount: The maximum number of visitor history entries to retrieve.
    /// - Returns: An array of visitor data objects.
    /// - Throws: An `APIError` if the request fails.
    public static func getVisitorHistory(serverURL: URL,
                                  forDeviceID deviceID: String,
                                  deviceKey: String? = nil,
                                  amount: Int) async throws -> [MiataruVisitor] {
        
        let url = serverURL.appendingPathComponent("v1/GetVisitorHistory")

        let requestBody = GetVisitorHistoryRequestBody(
            MiataruGetVisitorHistory: GetVisitorHistoryPayload(Device: deviceID, Amount: String(amount), DeviceKey: deviceKey)
        )

        let data: Data
        do {
            data = try await performPostRequest(url: url, encodablePayload: requestBody) {
                "[MiataruAPIClient] Requesting visitor history for device \(deviceID) amount=\(amount) payload=\($0)"
            }
        } catch APIError.encodingError(let err) {
            debugLog("[MiataruAPIClient] Encoding visitor history request failed for device \(deviceID): \(err.localizedDescription)")
            throw APIError.encodingError(err)
        }

        do {
            let response = try jsonDecoder.decode(MiataruGetVisitorHistoryResponse.self, from: data)
            debugLog("[MiataruAPIClient] Received visitor history entries=\(response.MiataruVisitors.count) for device \(deviceID)")
            return response.MiataruVisitors
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                debugLog("[MiataruAPIClient] Visitor history decode failed for device \(deviceID). Payload=\(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }
    
    /// Fetches the visitor history for a specific device from the server, including server configuration.
    /// This version automatically requests all available visitor history entries from the server.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to fetch the visitor history for.
    ///   - deviceKey: The optional DeviceKey for authentication.
    ///   - amount: The maximum number of visitor history entries to retrieve. If nil, requests the maximum available from server.
    /// - Returns: The full response including server config and visitors.
    /// - Throws: An `APIError` if the request fails.
    public static func getVisitorHistoryWithConfig(serverURL: URL,
                                                   forDeviceID deviceID: String,
                                                   deviceKey: String? = nil,
                                                   amount: Int?) async throws -> MiataruGetVisitorHistoryResponse {
        
        let url = serverURL.appendingPathComponent("v1/GetVisitorHistory")
        
        // First request with a reasonable default to get server config
        let initialAmount = amount ?? 1000
        let requestBody = GetVisitorHistoryRequestBody(
            MiataruGetVisitorHistory: GetVisitorHistoryPayload(Device: deviceID, Amount: String(initialAmount), DeviceKey: deviceKey)
        )

        let data: Data
        do {
            data = try await performPostRequest(url: url, encodablePayload: requestBody) {
                "[MiataruAPIClient] Requesting visitor history for device \(deviceID) amount=\(initialAmount) payload=\($0)"
            }
        } catch APIError.encodingError(let err) {
            debugLog("[MiataruAPIClient] Encoding visitor history request failed for device \(deviceID): \(err.localizedDescription)")
            throw APIError.encodingError(err)
        }

        do {
            let response = try jsonDecoder.decode(MiataruGetVisitorHistoryResponse.self, from: data)
            debugLog("[MiataruAPIClient] Received visitor history entries=\(response.MiataruVisitors.count) for device \(deviceID), available=\(response.MiataruServerConfig.AvailableVisitorHistory), max=\(response.MiataruServerConfig.MaximumNumberOfVisitorHistory)")
            
            // If amount was nil and we got fewer than available, request again with the available count
            if amount == nil, let available = Int(response.MiataruServerConfig.AvailableVisitorHistory), available > response.MiataruVisitors.count {
                let secondRequestBody = GetVisitorHistoryRequestBody(
                    MiataruGetVisitorHistory: GetVisitorHistoryPayload(Device: deviceID, Amount: String(available), DeviceKey: deviceKey)
                )
                do {
                    let secondData = try await performPostRequest(url: url, encodablePayload: secondRequestBody) {
                        "[MiataruAPIClient] Requesting full visitor history for device \(deviceID) amount=\(available) payload=\($0)"
                    }
                    let fullResponse = try jsonDecoder.decode(MiataruGetVisitorHistoryResponse.self, from: secondData)
                    debugLog("[MiataruAPIClient] Received full visitor history entries=\(fullResponse.MiataruVisitors.count) for device \(deviceID)")
                    return fullResponse
                } catch {
                    // If second request fails, return the first response
                    debugLog("[MiataruAPIClient] Second visitor history request failed, using first response: \(error)")
                    return response
                }
            }
            
            return response
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                debugLog("[MiataruAPIClient] Visitor history decode failed for device \(deviceID). Payload=\(jsonString)")
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
        if let deviceKey = locationData.DeviceKey, !deviceKey.isEmpty {
            locationDict["DeviceKey"] = deviceKey
        }
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

    /// Deletes all location data (current, history, visitors) for a device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to delete data for.
    ///   - deviceKey: The optional DeviceKey for authentication.
    /// - Returns: The delete response including deleted count if provided.
    /// - Throws: An `APIError` if the request fails.
    public static func deleteLocation(serverURL: URL,
                                      deviceID: String,
                                      deviceKey: String? = nil) async throws -> MiataruDeleteLocationResponse {
        let url = serverURL.appendingPathComponent("v1/DeleteLocation")
        let requestBody = DeleteLocationRequestBody(
            MiataruDeleteLocation: DeleteLocationPayload(Device: deviceID, DeviceKey: deviceKey)
        )

        let data = try await performPostRequest(url: url, encodablePayload: requestBody) {
            "[MiataruAPIClient] Deleting location data for device \(deviceID) payload=\($0)"
        }

        do {
            return try jsonDecoder.decode(MiataruDeleteLocationResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Sets or changes the DeviceKey for a device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to set the key for.
    ///   - currentDeviceKey: The current key (required when changing an existing key).
    ///   - newDeviceKey: The new key to set.
    /// - Returns: The set key response.
    /// - Throws: An `APIError` if the request fails.
    public static func setDeviceKey(serverURL: URL,
                                    deviceID: String,
                                    currentDeviceKey: String? = nil,
                                    newDeviceKey: String) async throws -> MiataruSetDeviceKeyResponse {
        let url = serverURL.appendingPathComponent("v1/setDeviceKey")
        let requestBody = SetDeviceKeyRequestBody(
            MiataruSetDeviceKey: SetDeviceKeyPayload(DeviceID: deviceID,
                                                     CurrentDeviceKey: currentDeviceKey,
                                                     NewDeviceKey: newDeviceKey)
        )

        let data = try await performPostRequest(url: url, encodablePayload: requestBody) {
            "[MiataruAPIClient] Setting device key for device \(deviceID) payload=\($0)"
        }

        do {
            return try jsonDecoder.decode(MiataruSetDeviceKeyResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Sets or updates the allowed devices list for a device.
    ///
    /// - Parameters:
    ///   - serverURL: The base URL of the Miataru server.
    ///   - deviceID: The ID of the device to update.
    ///   - deviceKey: The DeviceKey for authentication.
    ///   - allowedDevices: The full list of allowed devices.
    /// - Returns: The response from the server.
    /// - Throws: An `APIError` if the request fails.
    public static func setAllowedDeviceList(serverURL: URL,
                                            deviceID: String,
                                            deviceKey: String,
                                            allowedDevices: [MiataruAllowedDevice]) async throws -> MiataruSetAllowedDeviceListResponse {
        let url = serverURL.appendingPathComponent("v1/setAllowedDeviceList")
        let requestBody = SetAllowedDeviceListRequestBody(
            MiataruSetAllowedDeviceList: SetAllowedDeviceListPayload(DeviceID: deviceID,
                                                                     DeviceKey: deviceKey,
                                                                     allowedDevices: allowedDevices)
        )

        let data = try await performPostRequest(url: url, encodablePayload: requestBody) {
            "[MiataruAPIClient] Setting allowed devices list for device \(deviceID) payload=\($0)"
        }

        do {
            return try jsonDecoder.decode(MiataruSetAllowedDeviceListResponse.self, from: data)
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
        } catch let error as APIError {
            throw error
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
            if let errorResponse = try? jsonDecoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorResponse.error)
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
        case serverError(statusCode: Int, message: String)
    }
} 
