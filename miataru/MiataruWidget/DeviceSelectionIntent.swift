import Foundation
import AppIntents

struct KnownDeviceEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")
    static var defaultQuery = KnownDeviceQuery()

    let id: String
    let name: String

    init(device: KnownDevice) {
        self.id = device.DeviceID
        self.name = device.DeviceName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(name))
    }
}

struct KnownDeviceQuery: EntityQuery {
    func entities(for identifiers: [KnownDeviceEntity.ID]) async throws -> [KnownDeviceEntity] {
        let devices = KnownDeviceStore.shared.devices.filter { identifiers.contains($0.DeviceID) }
        return devices.map { KnownDeviceEntity(device: $0) }
    }

    func suggestedEntities() async throws -> [KnownDeviceEntity] {
        KnownDeviceStore.shared.devices.map { KnownDeviceEntity(device: $0) }
    }
}

struct DeviceSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Device"

    @Parameter(title: "Device")
    var device: KnownDeviceEntity?
}
