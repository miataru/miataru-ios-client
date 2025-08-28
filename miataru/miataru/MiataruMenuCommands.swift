import SwiftUI

struct MiataruMenuCommands: Commands {
    @EnvironmentObject private var groupActionHandler: GroupActionHandler

    var body: some Commands {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            groupMenu
        } else {
            EmptyCommands()
        }
        #else
        groupMenu
        #endif
    }

    private var groupMenu: some Commands {
        CommandMenu(NSLocalizedString("groups", comment: "Menu title for groups")) {
            Button(NSLocalizedString("add_group", comment: "Add group")) {
                groupActionHandler.showAddGroup = true
            }
            .keyboardShortcut("G", modifiers: [.command, .shift])

            Button(NSLocalizedString("edit_selected_group", comment: "Edit selected group")) {
                groupActionHandler.editingGroup = groupActionHandler.currentGroup
            }
            .disabled(groupActionHandler.currentGroup == nil)
        }
    }
}

