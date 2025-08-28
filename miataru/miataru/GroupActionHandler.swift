import SwiftUI

/// Handles group related actions that might be triggered globally
/// through menu commands or other UI components. Designed to be
/// platform agnostic so it can be reused for a future Mac port.
@MainActor
class GroupActionHandler: ObservableObject {
    /// Controls presentation of the add-group sheet.
    @Published var showAddGroup: Bool = false
    /// Holds the group currently being edited.
    @Published var editingGroup: DeviceGroup? = nil
    /// Represents the group that is currently selected/visible in the UI.
    @Published var currentGroup: DeviceGroup? = nil

    /// Trigger display of the add group sheet.
    func addGroup() {
        showAddGroup = true
    }

    /// Trigger editing of the currently selected group.
    func editCurrentGroup() {
        editingGroup = currentGroup
    }
}

