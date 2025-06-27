import Foundation
import MiataruAPIClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Dispatch
import _Concurrency

// Globale Variable zum Beenden der Schleife
var shouldTerminate = false

// Signal-Handler für SIGINT (STRG+C)
signal(SIGINT) { _ in
    print("\nSIGINT empfangen, beende...", terminator: "\n")
    fflush(stdout)
    shouldTerminate = true
}

struct MiataruTestApp {
    static func main() async {
        let serverURL = URL(string: "https://service.miataru.com")!
        let testDeviceID = "BF0160F5-4138-402C-A5F0-DEB1AA1F4216"
        let testPostDeviceID = "test-post-device-id"

        while !shouldTerminate {
            // Zufällige Location erzeugen
            let longitude = String(format: "%.6f", Double.random(in: -180...180))
            let latitude = String(format: "%.6f", Double.random(in: -90...90))
            let accuracy = String(format: "%.1f", Double.random(in: 5...100))
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let updatePayload = UpdateLocationPayload(
                Device: testPostDeviceID,
                Timestamp: timestamp,
                Longitude: longitude,
                Latitude: latitude,
                HorizontalAccuracy: accuracy
            )
            do {
                print("Sende zufällige Location: \(latitude), \(longitude) (Genauigkeit: \(accuracy))")
                fflush(stdout)
                let ack = try await MiataruAPIClient.updateLocation(
                    serverURL: serverURL,
                    locationData: updatePayload,
                    enableHistory: true,
                    retentionTime: 30
                )
                print("UpdateLocation-ACK: \(ack)")
                fflush(stdout)
            } catch {
                print("Fehler beim Senden der Location: \(error)")
                fflush(stdout)
            }
            do {
                print("Starte GetLocation-Test...")
                fflush(stdout)
                let locations = try await MiataruAPIClient.getLocation(
                    serverURL: serverURL,
                    forDeviceIDs: [testDeviceID],
                    requestingDeviceID: nil
                )
                print("Ergebnis von GetLocation:")
                for loc in locations {
                    print(loc)
                }
            } catch {
                print("Fehler beim Abrufen der Location: \(error)")
            }
            if shouldTerminate {
                break
            }
            print("Warte 5 Sekunden bis zum nächsten Abruf...")
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        print("Programm beendet.")
    }
}

let group = DispatchGroup()
group.enter()
Task {
    await MiataruTestApp.main()
    group.leave()
}
group.wait() 