---
name: Merge Groups Into Devices
overview: Move the iPhone Groups list into the Devices view, with a divider and inline Groups + button, while preserving existing group features and navigation.
todos:
  - id: merge-ui
    content: Embed groups list and state into iPhone_DevicesView with divider + inline “+”
    status: completed
  - id: remove-tab
    content: Remove Groups tab from iPhone_RootView and verify tab indices
    status: completed
  - id: preserve-group-features
    content: Wire sheets/navigation/sort/delete/edit for groups in new section
    status: completed
  - id: sanity-check
    content: Verify devices + groups interactions don’t conflict
    status: completed
isProject: false
---

# Merge Groups Into Devices

## Context

- `TabView` currently hosts a separate Groups tab in [`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_RootView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_RootView.swift):
```17:27:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_RootView.swift
TabView(selection: $selectedTab) {
    iPhone_DevicesView()
        .tabItem {
            Label("devices", systemImage: "iphone.gen3.badge.location")
        }
        .tag(0)
    iPhone_GroupsView()
        .tabItem {
            Label("groups", systemImage: "person.3")
        }
        .tag(1)
```

- Devices list lives in [`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_DevicesView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_DevicesView.swift):
```31:38:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_DevicesView.swift
List {
    ForEach(store.devices) { device in
        if editMode == .inactive {
            NavigationLink(value: device.DeviceID) {
```

- Groups list and all group behaviors are in [`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_GroupsView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_GroupsView.swift).

## Plan

- Update `TabView` in [`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_RootView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_RootView.swift) to remove the Groups tab so the list no longer lives in its own tab.
- Extend `iPhone_DevicesView` to render a second list section for groups below the devices list, separated by a divider (likely a `Section` + `Divider()` or a styled section footer/header).
- Move the Groups list UI from `iPhone_GroupsView` into the new Groups section in `iPhone_DevicesView`, preserving:
  - group rows and navigation to `iPhone_GroupMapView`
  - swipe actions (delete/edit)
  - reordering and deletion
  - edit sheet (`GroupEditSheetContainer`)
- Add an inline “+” button in the Groups section header (per your selection), wired to the existing `showingAddGroup` sheet.
- Keep existing devices list behaviors and toolbar (+ device, edit) intact.
- Ensure `DeviceGroupStore` is available in `iPhone_DevicesView` (already provided at the root), and add any missing state bindings needed to keep edit modes and selection independent between sections.

## Todos

- `merge-ui`: Embed groups list and state into `iPhone_DevicesView` with divider + inline “+”
- `remove-tab`: Remove Groups tab from `iPhone_RootView` and verify tab indices
- `preserve-group-features`: Wire up sheets/navigation/sort/delete/edit for groups in new section
- `sanity-check`: Verify devices + groups interactions don’t conflict (edit modes, navigation, sheets)