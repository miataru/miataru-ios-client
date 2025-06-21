import Foundation
import UIKit
import Combine

// Falls erforderlich, KnownDevice importieren (bei getrennten Modulen):
// import miataru

class KnownDeviceStore: ObservableObject {
    @Published var devices: [KnownDevice] = [] {
        didSet {
            setupSubscribers()
            save()
        }
    }
    private let fileName = "knownDevices.plist"
    private var cancellables: [AnyCancellable] = []

    private var fileURL: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        // Verzeichnis anlegen, falls nicht vorhanden
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectory.appendingPathComponent(fileName)
    }

    init() {
        self.devices = load()
        setupSubscribers()
    }

    private func setupSubscribers() {
        cancellables = []
        for device in devices {
            let c = device.objectWillChange
                .sink { [weak self] _ in
                    self?.save()
                }
            cancellables.append(c)
        }
    }

    private func save() {
       /* do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Fehler beim Speichern der KnownDevices: \(error)")
        }*/
        print("Speichern ist temporär deaktiviert - muss repariert werden!!!")
    }

    private func load() -> [KnownDevice] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let devices = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, KnownDevice.self, UIColor.self], from: data) as? [KnownDevice] {
                return devices
            }
        } catch {
            print("Fehler beim Laden der KnownDevices: \(error)")
        }
        return []
    }
} 
