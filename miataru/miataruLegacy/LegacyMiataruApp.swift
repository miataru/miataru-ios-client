/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LegacyMiataruApp.swift
 * miataru-iOS15
 *
 * Minimal iOS/iPadOS 15 compatible app surface.
 */

import AVFoundation
import CodeScanner
import CoreImage
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import UserNotifications

private extension UserDefaults {
    var legacyHasCompletedOnboarding: Bool {
        get { bool(forKey: "hasCompletedOnboarding") }
        set { set(newValue, forKey: "hasCompletedOnboarding") }
    }
}

final class LegacyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct LegacyMiataruApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(LegacyAppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        SettingsMigration.applyExistingInstallDefaultsIfNeeded(defaults: .standard)
        SettingsManager.shared.registerDefaultsFromSettingsBundle()
        _ = thisDeviceIDManager.shared.deviceID
        if SettingsManager.shared.trackAndReportLocation {
            LocationManager.shared.requestLocationPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            LegacyRootView()
                .environmentObject(settings)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    LegacyOnboardingView(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { if !$0 { hasCompletedOnboarding = true } }
                    ))
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                LocationManager.shared.appDidEnterForeground()
            case .background:
                LocationManager.shared.appDidEnterBackground()
            default:
                break
            }
        }
    }
}

private struct LegacyRootView: View {
    var body: some View {
        TabView {
            LegacyDevicesView()
                .tabItem {
                    Label("Devices", systemImage: "location.circle")
                }

            LegacyGroupsView()
                .tabItem {
                    Label("Groups", systemImage: "person.3")
                }

            LegacySettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

private struct LegacyOnboardingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var settings: SettingsManager
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                LegacyOnboardingPage(
                    systemImage: "location.viewfinder",
                    title: "Your location, your control",
                    message: "Choose your server, decide when this device reports, and share only the device IDs you trust."
                )
                .tag(0)

                LegacyOnboardingPage(
                    systemImage: "qrcode.viewfinder",
                    title: "Add devices with QR codes",
                    message: "Scan or share a miataru device link to connect devices without typing long IDs."
                )
                .tag(1)

                LegacyOnboardingPage(
                    systemImage: "location.fill",
                    title: "Enable tracking when you are ready",
                    message: "Location reporting stays off until you turn it on. iOS will ask for permission when needed."
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

            HStack {
                Button("Skip") {
                    complete()
                }
                Spacer()
                Button(page == 2 ? "Done" : "Next") {
                    if page == 2 {
                        complete()
                    } else {
                        withAnimation {
                            page += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private func complete() {
        UserDefaults.standard.legacyHasCompletedOnboarding = true
        isPresented = false
        if settings.trackAndReportLocation {
            LocationManager.shared.requestLocationPermission()
        }
    }
}

private struct LegacyOnboardingPage: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

private struct LegacyDevicesView: View {
    @ObservedObject private var store = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @State private var isAddingDevice = false
    @State private var isRefreshing = false
    @State private var refreshMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    LegacyMapView(devices: store.devices, locations: cache.locations)
                        .frame(minHeight: 240)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(store.devices) { device in
                        NavigationLink(destination: LegacyDeviceDetailView(device: device)) {
                            LegacyDeviceRow(device: device, location: cache.getLocation(for: device.DeviceID))
                        }
                    }
                    .onDelete(perform: deleteDevices)
                }

                if let refreshMessage {
                    Section {
                        Text(refreshMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: refreshLocations) {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)

                    Button(action: { isAddingDevice = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingDevice) {
                LegacyAddDeviceView(isPresented: $isAddingDevice)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func deleteDevices(at offsets: IndexSet) {
        store.remove(atOffsets: offsets)
    }

    private func refreshLocations() {
        isRefreshing = true
        refreshMessage = nil
        Task { @MainActor in
            let succeeded = await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: false)
            isRefreshing = false
            refreshMessage = succeeded ? "Locations updated." : "Could not update locations."
        }
    }
}

private struct LegacyDeviceRow: View {
    @ObservedObject var device: KnownDevice
    let location: CachedDeviceLocation?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(device.DeviceColor ?? UIColor.systemBlue))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.DeviceName.isEmpty ? "Unnamed device" : device.DeviceName)
                    .font(.headline)
                Text(device.DeviceID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let location {
                    Text(LegacyFormatters.locationSummary(location))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct LegacyDeviceDetailView: View {
    @ObservedObject var device: KnownDevice
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var store = KnownDeviceStore.shared
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    private var shareText: String {
        "miataru://\(device.DeviceID)"
    }

    var body: some View {
        List {
            Section {
                LegacyMapView(devices: [device], locations: cache.locations)
                    .frame(minHeight: 240)
                    .listRowInsets(EdgeInsets())
            }

            Section(header: Text("Device")) {
                TextField("Name", text: $device.DeviceName)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(device.DeviceID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                Toggle("Current location access", isOn: $device.hasCurrentLocationAccess)
                Toggle("History access", isOn: $device.hasHistoryAccess)
            }

            if let location = cache.getLocation(for: device.DeviceID) {
                Section(header: Text("Last Location")) {
                    Text(LegacyFormatters.locationSummary(location))
                    Text("Updated \(LegacyFormatters.dateTime.string(from: location.timestamp))")
                    if let batteryLevel = location.batteryLevel {
                        Text("Battery \(Int(batteryLevel))%")
                    }
                }
            }

            Section(header: Text("Share")) {
                if let image = LegacyQRCodeRenderer.image(for: shareText) {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .accessibilityLabel("Device QR code")
                        Spacer()
                    }
                }

                Button {
                    shareItems = [shareText]
                    showingShareSheet = true
                } label: {
                    Label("Share Device Link", systemImage: "square.and.arrow.up")
                }
            }

            if device.DeviceID != thisDeviceIDManager.shared.deviceID {
                Section {
                    Button {
                        store.removeDevice(byID: device.DeviceID)
                    } label: {
                        Text("Remove Device")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle(device.DeviceName.isEmpty ? "Device" : device.DeviceName)
        .sheet(isPresented: $showingShareSheet) {
            LegacyActivityView(activityItems: shareItems)
        }
    }
}

private struct LegacyAddDeviceView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var store = KnownDeviceStore.shared
    @State private var deviceName = ""
    @State private var deviceID = ""
    @State private var errorMessage: String?
    @State private var isShowingScanner = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device")) {
                    TextField("Name", text: $deviceName)
                    TextField("Device ID", text: $deviceID)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)

                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addDevice()
                    }
                    .disabled(normalizedDeviceID.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                CodeScannerView(codeTypes: [.qr]) { result in
                    switch result {
                    case .success(let scan):
                        deviceID = LegacyQRCodeParser.deviceID(from: scan.string)
                        if deviceName.isEmpty {
                            deviceName = "Device"
                        }
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                    isShowingScanner = false
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var normalizedDeviceID: String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func addDevice() {
        let id = normalizedDeviceID
        guard !id.isEmpty else { return }

        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = KnownDevice(name: name.isEmpty ? "Device" : name, deviceID: id, color: UIColor.systemBlue)
        if store.add(device: device) {
            isPresented = false
        } else {
            errorMessage = "A device with this ID already exists."
        }
    }
}

private struct LegacyGroupsView: View {
    @ObservedObject private var store = DeviceGroupStore.shared
    @State private var isAddingGroup = false
    @State private var newGroupName = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(store.groups) { group in
                    NavigationLink(destination: LegacyGroupDetailView(group: group)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.groupName)
                                .font(.headline)
                            Text("\(group.deviceIDs.count) devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete(perform: store.remove)
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isAddingGroup = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingGroup) {
                NavigationView {
                    Form {
                        TextField("Group name", text: $newGroupName)
                    }
                    .navigationTitle("New Group")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                newGroupName = ""
                                isAddingGroup = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    store.add(group: DeviceGroup(name: trimmed))
                                }
                                newGroupName = ""
                                isAddingGroup = false
                            }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct LegacyGroupDetailView: View {
    @ObservedObject var group: DeviceGroup
    @ObservedObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared

    private var groupDevices: [KnownDevice] {
        deviceStore.devices.filter { group.deviceIDs.contains($0.DeviceID) }
    }

    var body: some View {
        List {
            Section {
                LegacyMapView(devices: groupDevices, locations: cache.locations)
                    .frame(minHeight: 240)
                    .listRowInsets(EdgeInsets())
            }

            Section(header: Text("Group")) {
                TextField("Name", text: $group.groupName)
            }

            Section(header: Text("Devices")) {
                ForEach(deviceStore.devices) { device in
                    Toggle(isOn: Binding(
                        get: { group.containsDevice(device.DeviceID) },
                        set: { _ in group.toggleDevice(device.DeviceID) }
                    )) {
                        LegacyDeviceRow(device: device, location: cache.getLocation(for: device.DeviceID))
                    }
                }
            }
        }
        .navigationTitle(group.groupName.isEmpty ? "Group" : group.groupName)
    }
}

private struct LegacySettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    private var ownDeviceLink: String {
        "miataru://\(thisDeviceIDManager.shared.deviceID)"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("This Device")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Device ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(thisDeviceIDManager.shared.deviceID)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    if let image = LegacyQRCodeRenderer.image(for: ownDeviceLink) {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 160)
                            Spacer()
                        }
                    }

                    Button {
                        shareItems = [ownDeviceLink]
                        showingShareSheet = true
                    } label: {
                        Label("Share My Device Link", systemImage: "square.and.arrow.up")
                    }
                }

                Section(header: Text("Server")) {
                    TextField("Server URL", text: $settings.miataruServerURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Device Key", text: Binding(
                        get: { settings.deviceKey ?? "" },
                        set: { settings.deviceKey = $0.isEmpty ? nil : $0 }
                    ))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                }

                Section(header: Text("Location")) {
                    Toggle("Track and report location", isOn: $settings.trackAndReportLocation)
                    Toggle("Save location history on server", isOn: $settings.saveLocationHistoryOnServer)
                    Toggle("Auto refresh device list", isOn: $settings.autoRefreshDeviceList)
                    Button("Request Location Permission") {
                        LocationManager.shared.requestLocationPermission()
                    }
                    Text("Authorization: \(LegacyFormatters.authorizationStatus(locationManager.authorizationStatus))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if let lastServerUpdate = locationManager.lastServerUpdate {
                        Text("Last server update: \(LegacyFormatters.dateTime.string(from: lastServerUpdate))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Map")) {
                    Picker("Map Type", selection: $settings.mapType) {
                        Text("Standard").tag(0)
                        Text("Satellite").tag(1)
                        Text("Hybrid").tag(2)
                    }
                    Toggle("Indicate accuracy", isOn: $settings.indicateAccuracyOnMap)
                    Stepper("Map refresh: \(settings.mapUpdateInterval)s", value: $settings.mapUpdateInterval, in: 5...600, step: 5)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingShareSheet) {
                LegacyActivityView(activityItems: shareItems)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct LegacyMapView: UIViewRepresentable {
    let devices: [KnownDevice]
    let locations: [CachedDeviceLocation]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)

        let annotations = devices.compactMap { device -> MKPointAnnotation? in
            guard let location = locations.first(where: { $0.deviceID == device.DeviceID }) else { return nil }
            let annotation = MKPointAnnotation()
            annotation.title = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
            annotation.subtitle = LegacyFormatters.locationSummary(location)
            annotation.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            return annotation
        }

        mapView.addAnnotations(annotations)
        if !annotations.isEmpty {
            mapView.showAnnotations(annotations, animated: false)
        } else if let userLocation = mapView.userLocation.location {
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            )
            mapView.setRegion(region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "LegacyDeviceAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = .systemBlue
            return view
        }
    }
}

private struct LegacyActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum LegacyQRCodeParser {
    static func deviceID(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           url.scheme?.lowercased() == "miataru",
           let host = url.host,
           !host.isEmpty {
            return host.uppercased()
        }

        let prefix = "miataru://"
        if trimmed.lowercased().hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).uppercased()
        }

        return trimmed.uppercased()
    }
}

private enum LegacyQRCodeRenderer {
    static func image(for string: String) -> UIImage? {
        guard let data = string.data(using: .isoLatin1),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private enum LegacyFormatters {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func locationSummary(_ location: CachedDeviceLocation) -> String {
        var parts: [String] = []
        if let locality = location.locality, !locality.isEmpty {
            parts.append(locality)
        }
        if let country = location.country, !country.isEmpty {
            parts.append(country)
        }
        let place = parts.isEmpty ? "Location" : parts.joined(separator: ", ")
        return "\(place) at \(dateTime.string(from: location.timestamp))"
    }

    static func authorizationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways:
            return "Always"
        case .authorizedWhenInUse:
            return "When in use"
        @unknown default:
            return "Unknown"
        }
    }
}
