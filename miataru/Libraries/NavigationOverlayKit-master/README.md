# NavigationOverlayKit

NavigationOverlayKit is a Swift Package that provides a ready-to-use SwiftUI overlay component for displaying navigation instructions derived from `MKRoute` and `MKDirections`. The overlay shows a navigation arrow, a textual instruction, and distance information to help users stay on track during turn-by-turn navigation experiences.

## Features

- 📍 SwiftUI overlay view designed for in-app navigation experiences.
- 🧭 Support for `MKRoute` and `MKRoute.Step` instructions out-of-the-box.
- 🔁 Observable view model that can react to navigation progress updates.
- 🧰 Lightweight Swift Package ready for integration into other projects, including ToiletFinder.

## Requirements

- iOS 15.0+
- Xcode 15+

## Installation

### Swift Package Manager (SPM)

1. In Xcode, open **File → Add Packages...**
2. Enter the repository URL of NavigationOverlayKit.
3. Select **Add Package** and ensure the `NavigationOverlayKit` library is added to your target.

## Usage

### 1. Import the library

```swift
import NavigationOverlayKit
```

### 2. Create a view model

You can construct the provided `NavigationOverlayViewModel` with a MapKit `MKRoute`. The view model keeps track of the current instruction and updates the overlay automatically when you move between steps.

```swift
let directionsRequest = MKDirections.Request()
directionsRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoordinate))
directionsRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))

let directions = MKDirections(request: directionsRequest)
directions.calculate { response, error in
    guard let route = response?.routes.first else { return }
    let viewModel = NavigationOverlayViewModel(route: route, unit: .kilometers)
    // Store viewModel for later use in your SwiftUI view hierarchy.
}
```

### 3. Display the overlay

Attach the overlay to any SwiftUI view (for example, a map) and provide the shared view model:

```swift
struct ContentView: View {
    @StateObject private var viewModel: NavigationOverlayViewModel

    init(route: MKRoute) {
        _viewModel = StateObject(wrappedValue: NavigationOverlayViewModel(route: route, unit: .kilometers))
    }

    var body: some View {
        ZStack {
            Map(route: route)
            NavigationOverlayView(viewModel: viewModel, alignment: .top)
        }
    }
}
```

### 4. Updating navigation progress

When you receive live navigation updates (e.g. from `CLLocationManager` callbacks), call the appropriate methods on the view model to refresh the overlay:

```swift
func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let currentRoute = currentRoute else { return }
    let stepIndex = navigationEngine.currentStepIndex(for: locations.last, on: currentRoute)
    viewModel.update(step: stepIndex)
}
```

Alternatively, construct custom instructions directly:

```swift
let instruction = NavigationInstruction(
    text: "Turn right onto Market Street",
    distance: Measurement(value: 120, unit: .meters),
    symbol: .right
)
viewModel.update(with: instruction)
```

### 5. Reacting to instruction symbol changes (haptics/sound)

`NavigationOverlayViewModel` publishes the current `symbol` so apps can subscribe and trigger haptics/audio cues whenever a new instruction is decoded:

```swift
@StateObject private var viewModel = NavigationOverlayViewModel()
@State private var cancellables = Set<AnyCancellable>()

func bindHaptics() {
    viewModel.$symbol
        .compactMap { $0 }
        .sink { symbol in
            let generator: UIImpactFeedbackGenerator
            switch symbol {
            case .uTurn, .arrive:
                generator = UIImpactFeedbackGenerator(style: .heavy)
            case .left, .right, .sharpLeft, .sharpRight:
                generator = UIImpactFeedbackGenerator(style: .medium)
            case .slightLeft, .slightRight:
                generator = UIImpactFeedbackGenerator(style: .light)
            case .start, .straight, .cross, .tunnel, .bridge, .stairs, .escalator:
                generator = UIImpactFeedbackGenerator(style: .soft)
            }
            generator.impactOccurred()
        }
        .store(in: &cancellables)
}
```

## Integration guidance (Xcode + SwiftUI)

- Prefer `@StateObject` for `NavigationOverlayViewModel` when the overlay is owned by a view, so the model persists across view reloads.
- If you need to share the overlay across multiple views, inject the view model via `@EnvironmentObject` or a custom dependency container.
- Use `updateRemainingDistance(to:)` for frequent distance refreshes without changing the current instruction, and `update(step:)` when you advance between route steps.
- In UIKit-backed projects, host the overlay via `UIHostingController` and keep the view model in your coordinator or view controller.

## Versioning

NavigationOverlayKit follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

- `MAJOR` for breaking API changes.
- `MINOR` for backwards-compatible feature additions.
- `PATCH` for backwards-compatible bug fixes.

The current library version is exposed via `NavigationOverlayKitVersion.current`.

> Note: Swift Package Manager does not support declaring a version inside `Package.swift`.
> Versions are published via Git tags, so keep tags in sync with `NavigationOverlayKitVersion.current`.

### How Xcode determines updates

Xcode relies on Swift Package Manager to resolve dependency versions based on your package requirement
(exact, branch, or version range). When you choose **File → Packages → Update to Latest Package Versions**
or trigger a dependency resolve, SwiftPM fetches the latest matching Git tags for each package, updates
`Package.resolved`, and Xcode uses that lockfile to decide whether a newer compatible version is available.

## Example

An end-to-end example showing how to use NavigationOverlayKit within a simple SwiftUI view:

```swift
struct RoutePreview: View {
    @State private var route: MKRoute?
    @StateObject private var viewModel = NavigationOverlayViewModel()

    var body: some View {
        ZStack {
            MapRouteView(route: $route)
            NavigationOverlayView(viewModel: viewModel)
        }
        .task {
            await loadRoute()
        }
    }

    private func loadRoute() async {
        do {
            let calculatedRoute = try await RouteLoader().route(from: startCoordinate, to: destinationCoordinate)
            route = calculatedRoute
            viewModel.update(step: 0)
        } catch {
            print("Failed to fetch route: \(error)")
        }
    }
}
```

> ℹ️ `MapRouteView` and `RouteLoader` are placeholders representing your map view and routing logic.

## Folder Structure

```
NavigationOverlayKit/
├── Package.swift
├── README.md
├── Sources/
│   └── NavigationOverlayKit/
│       ├── NavigationInstruction.swift
│       ├── NavigationOverlayView.swift
│       ├── NavigationOverlayViewModel.swift
│       └── Resources/
└── Tests/
    └── NavigationOverlayKitTests/
```

## Multilingual maneuver mapping (community‑maintained)

NavigationOverlayKit derives maneuver symbols (left/right/slight/sharp/U‑turn/arrive) from `MKRoute`/`MKRoute.Step`.

- MapKit provides localized, free‑text step instructions but no typed maneuver enum.
- To support multiple locales, the kit:
  - First tries a multilingual keyword map (English, German, French, Spanish, Italian, Japanese; easy to extend)
  - Then falls back to geometry‑based angle detection between step polylines
  - Finally defaults to straight when neither approach is decisive

Why this exists: Without a typed maneuver in MapKit, mapping across all locales requires heuristics. This hybrid approach is practical but community help improves coverage and accuracy.

### How you can help

- Add keywords for your language in `NavigationInstruction.symbolFromLocalizedInstruction(_:)`.
  - Include variants, gendered/plural forms, and common synonyms.
  - Keep tokens lowercase; accents are fine. Prefer short substrings that are unlikely to conflict.
- Add unit tests in `NavigationOverlayKitTests` with real instructions captured from MapKit for your locale.
- If you see a mis‑classified turn, open an issue and include:
  - Locale and full instruction text
  - Expected maneuver (e.g., sharpLeft)
  - Optional: previous/current step coordinates for geometry fallback validation

If you need guaranteed correctness across many languages, consider using a routing SDK that exposes typed maneuvers (e.g., Mapbox or HERE) and feed its steps into `NavigationOverlayViewModel`.

## Screenshot
![Simulator Screenshot - iPhone 17 Pro Max - 2025-10-11 at 16.12.14.png](https://github.com/bietiekay/NavigationOverlayKit/blob/master/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20Max%20-%202025-10-11%20at%2016.12.14.png)

## License

NavigationOverlayKit is provided with BSD 2-Clause "Simplified" License. See LICENSE file.
