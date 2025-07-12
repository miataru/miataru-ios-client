// DeviceLocationCacheStore speichert die letzte bekannte Location jedes Devices lokal (analog zu DeviceGroupStore/KnownDeviceStore)
// Siehe README oder DeviceGroupStore für Details zum Speicherort und Format.
import Foundation
import UIKit
import Combine

@objc(CachedDeviceLocation)
class CachedDeviceLocation: NSObject, NSCoding, NSSecureCoding, Identifiable {
    @objc var deviceID: String
    @objc var latitude: Double
    @objc var longitude: Double
    @objc var accuracy: Double
    @objc var timestamp: Date
    
    var id: String { deviceID }
    
    init(deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date) {
        self.deviceID = deviceID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.deviceID = aDecoder.decodeObject(forKey: "deviceID") as? String ?? ""
        self.latitude = aDecoder.decodeDouble(forKey: "latitude")
        self.longitude = aDecoder.decodeDouble(forKey: "longitude")
        self.accuracy = aDecoder.decodeDouble(forKey: "accuracy")
        self.timestamp = aDecoder.decodeObject(forKey: "timestamp") as? Date ?? Date()
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(deviceID, forKey: "deviceID")
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(accuracy, forKey: "accuracy")
        aCoder.encode(timestamp, forKey: "timestamp")
    }
    
    static var supportsSecureCoding: Bool {
        return true
    }
}

class DeviceLocationCacheStore: ObservableObject {
    static let shared = DeviceLocationCacheStore()
    
    @Published var locations: [CachedDeviceLocation] = [] {
        didSet {
            save()
        }
    }
    private let fileName = "deviceLocations.plist"
    
    private var fileURL: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectory.appendingPathComponent(fileName)
    }
    
    private init() {
        self.locations = load()
    }
    
    private func save() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: locations, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Fehler beim Speichern der DeviceLocations: \(error)")
        }
    }
    
    private func load() -> [CachedDeviceLocation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let locations = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, CachedDeviceLocation.self], from: data) as? [CachedDeviceLocation] {
                return locations
            }
        } catch {
            print("Fehler beim Laden der DeviceLocations: \(error)")
        }
        return []
    }
    
    func setLocation(for deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date) {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            locations[idx] = CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp)
        } else {
            locations.append(CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp))
        }
    }
    
    func getLocation(for deviceID: String) -> CachedDeviceLocation? {
        return locations.first(where: { $0.deviceID == deviceID })
    }
    
    func removeLocation(for deviceID: String) {
        locations.removeAll { $0.deviceID == deviceID }
    }
} 