import Foundation
import UIKit
import Combine

class DeviceGroupStore: ObservableObject {
    @Published var groups: [DeviceGroup] = [] {
        didSet {
            setupSubscribers()
            save()
        }
    }
    private let fileName = "deviceGroups.plist"
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
        self.groups = load()
        setupSubscribers()
    }

    private func setupSubscribers() {
        cancellables = []
        for group in groups {
            let c = group.objectWillChange
                .sink { [weak self] _ in
                    self?.save()
                }
            cancellables.append(c)
        }
    }

    private func save() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: groups, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            print("Fehler beim Speichern der DeviceGroups: \(error)")
        }
    }

    private func load() -> [DeviceGroup] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let groups = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, DeviceGroup.self, UIColor.self], from: data) as? [DeviceGroup] {
                // Nach gespeicherter Reihenfolge sortieren
                return groups.sorted { $0.groupPosition < $1.groupPosition }
            }
        } catch {
            print("Fehler beim Laden der DeviceGroups: \(error)")
        }
        return []
    }

    func add(group: DeviceGroup) {
        groups.append(group)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        // Reihenfolge-Index aktualisieren
        for (index, group) in groups.enumerated() {
            group.groupPosition = index
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        groups.remove(atOffsets: offsets)
        save()
    }
    
    func remove(group: DeviceGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups.remove(at: index)
        }
    }
    
    func getGroupsForDevice(_ deviceID: String) -> [DeviceGroup] {
        return groups.filter { $0.containsDevice(deviceID) }
    }
} 