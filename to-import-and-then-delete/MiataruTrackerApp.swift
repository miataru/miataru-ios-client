import SwiftUI
import MapKit
import CoreLocation

/// Eine Struktur für die Kartenanmerkung, um sie für die `Map`-Ansicht von SwiftUI identifizierbar zu machen.
struct DeviceLocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Das ViewModel, das für das Abrufen und Verwalten der Standortdaten zuständig ist.
@MainActor
class LocationViewModel: ObservableObject {
    /// Die Anmerkung, die auf der Karte angezeigt werden soll.
    @Published var annotation: DeviceLocationAnnotation?
    
    /// Die Region der Karte, die angezeigt werden soll.
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.507222, longitude: -0.1275), // Standardmäßig London
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    // --- KONFIGURATION ---
    // Bitte ändere diese Werte, damit sie zu deinem Miataru-Server und Gerät passen.
    private let serverURL = URL(string: "https://locator.miataru.com")!
    let deviceID = "YOUR_DEVICE_ID" // <-- WICHTIG: DIES ÄNDERN
    // -------------------

    private var timer: Timer?

    init() {
        startFetchingLocation()
    }

    deinit {
        // Den Timer ungültig machen, wenn das ViewModel dealloziert wird.
        timer?.invalidate()
    }

    /// Startet einen Timer, um den Standort regelmäßig abzurufen.
    func startFetchingLocation() {
        // Sofort einmal abrufen.
        Task {
            await fetchLocation()
        }
        
        // Einen Timer einrichten, der den Standort alle 5 Sekunden abruft.
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchLocation()
            }
        }
    }

    /// Ruft den Standort vom Miataru-Server ab.
    private func fetchLocation() async {
        guard deviceID != "YOUR_DEVICE_ID" else {
            print("Bitte konfiguriere deine deviceID im LocationViewModel.")
            return
        }
        
        do {
            // Den MiataruAPIClient verwenden, um Standortdaten zu erhalten.
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: serverURL,
                forDeviceIDs: [deviceID],
                requestingDeviceID: nil // Du kannst bei Bedarf eine anfragende Geräte-ID angeben.
            )

            // Den ersten in der Antwort gefundenen Standort verarbeiten.
            if let location = locations.first {
                // Die Zeichenketten-Koordinaten für MapKit in Double umwandeln.
                if let lat = Double(location.Latitude), let lon = Double(location.Longitude) {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    
                    // Die Anmerkung und die Kartenregion auf dem Hauptthread aktualisieren.
                    self.annotation = DeviceLocationAnnotation(coordinate: coordinate)
                    self.mapRegion.center = coordinate
                }
            }
        } catch {
            // Fehler während des Abrufs behandeln und ausgeben.
            print("Fehler beim Abrufen des Standorts: \(error.localizedDescription)")
        }
    }
}

/// Der Haupteinstiegspunkt der Anwendung.
@main
struct MiataruTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Die Hauptansicht der Anwendung.
struct ContentView: View {
    // Den Lebenszyklus des LocationViewModel erstellen und verwalten.
    @StateObject private var viewModel = LocationViewModel()

    var body: some View {
        // Einen ZStack verwenden, um eine Lade-/Informationsansicht über die Karte zu legen.
        ZStack {
            // Die Kartenansicht, gebunden an die Region und die Anmerkungen des ViewModels.
            Map(coordinateRegion: $viewModel.mapRegion,
                annotationItems: viewModel.annotation.map { [$0] } ?? []) { item in
                MapPin(coordinate: item.coordinate, tint: .red)
            }
            .edgesIgnoringSafeArea(.all)

            // Eine Meldung anzeigen, wenn die Geräte-ID nicht konfiguriert ist oder noch kein Standort gefunden wurde.
            if viewModel.annotation == nil {
                VStack(spacing: 8) {
                    if viewModel.deviceID == "YOUR_DEVICE_ID" {
                        Text("Bitte konfiguriere die `deviceID` in der `MiataruTrackerApp.swift` Datei.")
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Suche Standort...")
                        ProgressView()
                    }
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(10)
            }
        }
    }
} 