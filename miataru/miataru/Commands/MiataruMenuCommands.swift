import SwiftUI

struct MiataruMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("New Device Window") {
                openWindow(id: "deviceWindow")
            }
        }
    }
}
