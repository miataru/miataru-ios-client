# AnimatedMapPolyline

A SwiftUI-based demonstration project that showcases animated route drawing on a map. This project contains both the **AnimatedPolylineKit** library and a **Demo application** that demonstrates its usage.

## Overview

AnimatedMapPolyline provides a complete solution for displaying and animating routes on Apple Maps using SwiftUI. The project demonstrates how to:

- Draw routes on a map using MapKit
- Animate route polylines
- Display start and end markers with custom colors
- Generate random routes between locations
- Integrate MapKit with SwiftUI using `UIViewRepresentable`

## Project Structure

The project consists of two main components:

### AnimatedPolylineKit Library

A reusable library component (to be extracted) that provides functionality for:
- Creating animated polylines on maps
- Managing route overlays
- Customizing route appearance (color, width, line caps, etc.)

### Demo Application

A SwiftUI demo application that showcases the library's capabilities:
- Interactive map view with route visualization
- Random route generation between predefined locations
- Start (green) and end (red) markers
- Refresh button to generate new routes

## Features

- ✅ SwiftUI-based map integration
- ✅ Route calculation using MapKit Directions API
- ✅ Animated route drawing
- ✅ Custom marker colors
- ✅ Random route generation
- ✅ Automatic map region adjustment to fit routes
- ✅ Support for routes up to 50km

## Requirements

- iOS 14.0+ / macOS 11.0+ / watchOS 7.0+ / tvOS 14.0+
- Xcode 12.0+
- Swift 5.0+

## Usage

### Basic Setup

1. Open the project in Xcode
2. Build and run the application
3. The app will automatically generate a random route on launch
4. Tap the refresh button (circular arrow icon) to generate a new route

### Using the Map View

The `MapView` component can be integrated into your SwiftUI views:

```swift
MapView(
    region: $region,
    markers: markers,
    polyline: routePolyline
)
```

### Generating Routes

The `MapViewModel` handles route generation and calculation:

```swift
let viewModel = MapViewModel()
viewModel.generateRandomRoute()
```

## Architecture

The project follows a clean architecture pattern:

- **ContentView**: Main SwiftUI view that displays the map
- **MapView**: `UIViewRepresentable` wrapper for `MKMapView`
- **MapViewModel**: Observable object managing map state and route calculations
- **MapMarker**: Model representing map markers with coordinates and colors

## Sample Locations

The demo includes predefined locations across the United States:
- San Francisco, CA
- New York, NY
- Los Angeles, CA
- Chicago, IL
- Miami, FL
- Seattle, WA
- Boston, MA
- Austin, TX
- Denver, CO
- Portland, OR

Routes are generated between locations within 50km of each other, or random points are created if no nearby predefined locations exist.

## License

This project is licensed under the 2-Clause BSD License. See [LICENSE.md](LICENSE.md) for details.

## Author

Daniel Kirstenpfad  
https://miataru.com

## Copyright

Copyright © 2026 Daniel Kirstenpfad. All rights reserved.
