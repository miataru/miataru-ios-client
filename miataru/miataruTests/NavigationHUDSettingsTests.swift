import Testing
import Foundation
import CoreLocation
@testable import miataru

struct NavigationHUDSettingsTests {
    @Test("HUD speed is always km/h and hides location older than fifteen seconds")
    func speedFormattingUsesFreshLocationAndKilometersPerHour() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func location(speed: CLLocationSpeed, age: TimeInterval) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: speed,
                timestamp: now.addingTimeInterval(-age)
            )
        }

        #expect(NavigationHUDView.speedText(for: location(speed: 10, age: 0), now: now) == "36")
        #expect(NavigationHUDView.speedText(for: location(speed: 10, age: 15), now: now) == "36")
        #expect(NavigationHUDView.speedText(for: location(speed: 10, age: 15.01), now: now) == "—")
        #expect(NavigationHUDView.speedText(for: location(speed: -1, age: 0), now: now) == "—")
        #expect(NavigationHUDView.speedText(for: nil, now: now) == "—")
    }

    @Test("HUD palette and mirror choice persist across settings store instances")
    @MainActor
    func paletteAndMirrorPreferencesPersist() throws {
        let suite = "NavigationHUDSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(NavigationHUDSettings(defaults: defaults).palette == .white)
        let first = NavigationHUDSettings(defaults: defaults)
        first.palette = .yellow
        first.isMirrored = true

        let reopened = NavigationHUDSettings(defaults: defaults)
        #expect(reopened.palette == .yellow)
        #expect(reopened.isMirrored)
    }

    @Test("Settings search matches localized labels and German HUD terms")
    func searchMatchesGermanAndEnglishTerms() {
        let entries = SettingsSearchIndex.entries()
        #expect(entries.contains { $0.key == "navigation_hud_section" && $0.matches("Geschwindigkeit") })
        #expect(entries.contains { $0.key == "navigation_hud_mirror" && $0.matches("Spiegel") })
        #expect(entries.contains { $0.key == "show_current_speed_on_map" && $0.matches("map speed") })
        #expect(entries.contains { $0.key == "manage_your_devicekey" && $0.matches("device key") })
        #expect(entries.first { $0.key == "allowed_device_list_section_title" }?.matches(String(localized: "allowed_device_list_enable_button", table: "Devices")) == true)
    }

    @Test("Settings search routes hidden controls to the correct prerequisite")
    func searchTargetsPrerequisitesBeforeHiddenControls() throws {
        let entries = SettingsSearchIndex.entries()
        let threshold = try #require(entries.first { $0.key == "smart_frequent_background_speed_threshold_title" })
        let duration = try #require(entries.first { $0.key == "frequent_background_location_updates_duration_title" })

        let permission = SettingsSearchIndex.target(
            for: threshold,
            trackingReady: false,
            saveHistoryOnServer: true,
            smartFrequentEnabled: false,
            frequentEnabled: false
        )
        #expect(permission.page == .main)
        #expect(permission.anchor == "settings.track-and-history")
        #expect(permission.isPrerequisite)

        let smartToggle = SettingsSearchIndex.target(
            for: duration,
            trackingReady: true,
            saveHistoryOnServer: true,
            smartFrequentEnabled: false,
            frequentEnabled: false
        )
        #expect(smartToggle.anchor == SettingsSearchIndex.anchor("smart_frequent_background_location_updates_title"))
        #expect(smartToggle.isPrerequisite)

        let manualToggle = SettingsSearchIndex.target(
            for: duration,
            trackingReady: true,
            saveHistoryOnServer: true,
            smartFrequentEnabled: true,
            frequentEnabled: false
        )
        #expect(manualToggle.anchor == SettingsSearchIndex.anchor("frequent_background_location_updates_title"))
        #expect(manualToggle.isPrerequisite)

        let durationControl = SettingsSearchIndex.target(
            for: duration,
            trackingReady: true,
            saveHistoryOnServer: true,
            smartFrequentEnabled: true,
            frequentEnabled: true
        )
        #expect(durationControl.anchor == duration.anchor)
        #expect(!durationControl.isPrerequisite)

        let visibleManualDuration = SettingsSearchIndex.target(
            for: duration,
            trackingReady: true,
            saveHistoryOnServer: true,
            smartFrequentEnabled: false,
            frequentEnabled: true
        )
        #expect(visibleManualDuration.anchor == duration.anchor)
        #expect(!visibleManualDuration.isPrerequisite)

        let trackingPause = try #require(entries.first { $0.key == "tracking_pause_settings_title" })
        let disabledTracking = SettingsSearchIndex.target(
            for: trackingPause,
            trackingReady: false,
            saveHistoryOnServer: true,
            smartFrequentEnabled: false,
            frequentEnabled: false,
            trackingEnabled: false
        )
        #expect(disabledTracking.page == .main)
        #expect(disabledTracking.anchor == SettingsSearchIndex.anchor("location_track"))
        #expect(disabledTracking.isPrerequisite)
    }

    @Test("HUD route and markers share one aspect-fit projection in portrait and landscape")
    func routeProjectionKeepsMarkersAlignedForBothOrientations() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0),
            CLLocationCoordinate2D(latitude: 52.001, longitude: 13.002),
            CLLocationCoordinate2D(latitude: 52.003, longitude: 13.004)
        ]
        let user = coordinates[0]
        let remote = coordinates[2]
        for size in [CGSize(width: 390, height: 760), CGSize(width: 760, height: 390)] {
            let projection = NavigationHUDProjection.project(
                routeCoordinates: coordinates,
                userCoordinate: user,
                remoteCoordinate: remote,
                size: size
            )
            let first = try #require(projection.route.first)
            let last = try #require(projection.route.last)
            #expect(projection.user == first)
            #expect(projection.remote == last)
            #expect(projection.route.allSatisfy { $0.x >= 0 && $0.x <= size.width && $0.y >= 0 && $0.y <= size.height })
        }
    }

    @Test("HUD forward focus follows real route geometry within the requested look-ahead")
    func forwardFocusWindowTracksCurrentLocation() throws {
        let route = (0...8).map { index in
            CLLocationCoordinate2D(latitude: 0, longitude: Double(index) * 0.005)
        }
        let user = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let focused = NavigationHUDFocusRoute.coordinates(
            route: route,
            userCoordinate: user,
            lookAheadMeters: 300,
            lookBehindMeters: 60
        )
        let first = try #require(focused.first)
        let last = try #require(focused.last)
        let origin = CLLocation(latitude: user.latitude, longitude: user.longitude)

        #expect(focused.count >= 3)
        #expect(abs(origin.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude)) - 60) < 8)
        #expect(abs(origin.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) - 300) < 8)

        let movedUser = CLLocationCoordinate2D(latitude: 0, longitude: 0.015)
        let movedFocus = NavigationHUDFocusRoute.coordinates(route: route, userCoordinate: movedUser, lookAheadMeters: 300)
        #expect(try #require(movedFocus.last).longitude > last.longitude)
    }

    @Test("HUD forward perspective anchors the user low and keeps the next turn visible")
    func forwardPerspectiveKeepsTurnVisibleInPortraitAndLandscape() throws {
        let route = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.006),
            CLLocationCoordinate2D(latitude: 0.006, longitude: 0.006)
        ]
        let user = CLLocationCoordinate2D(latitude: 0, longitude: 0.003)
        let focus = NavigationHUDFocusRoute.coordinates(route: route, userCoordinate: user, lookAheadMeters: 1_000)

        for size in [CGSize(width: 390, height: 760), CGSize(width: 760, height: 390)] {
            let projection = NavigationHUDProjection.project(
                routeCoordinates: focus,
                userCoordinate: user,
                remoteCoordinate: nil,
                size: size,
                alignForward: true
            )
            let userPoint = try #require(projection.user)
            let turnIndex = try #require(focus.firstIndex { abs($0.latitude - route[1].latitude) < 0.000_001 && abs($0.longitude - route[1].longitude) < 0.000_001 })
            let turn = projection.route[turnIndex]
            #expect(abs(userPoint.y - size.height * 0.78) < 1)
            #expect(turn.y < userPoint.y)
            #expect(projection.route.allSatisfy { $0.x >= 24 && $0.x <= size.width - 24 && $0.y >= 24 && $0.y <= size.height - 24 })
        }
    }

    @Test("HUD only reports compass or course heading when the source is valid and current")
    func headingResolutionRejectsStaleOrUnreliableCourse() throws {
        let compass = NavigationHUDHeading.resolve(
            compassDegrees: 123,
            compassIsValid: true,
            courseDegrees: nil,
            speed: nil,
            locationAge: nil
        )
        #expect(compass == NavigationHUDHeading(degrees: 123, source: .compass))

        let course = NavigationHUDHeading.resolve(
            compassDegrees: 45,
            compassIsValid: false,
            courseDegrees: 45,
            speed: 4,
            locationAge: 10
        )
        #expect(course == NavigationHUDHeading(degrees: 45, source: .course))
        #expect(NavigationHUDHeading.resolve(
            compassDegrees: 45,
            compassIsValid: false,
            courseDegrees: 45,
            speed: 0.5,
            locationAge: 2
        ) == nil)
        #expect(NavigationHUDHeading.resolve(
            compassDegrees: nil,
            compassIsValid: false,
            courseDegrees: 45,
            speed: 4,
            locationAge: 15.1
        ) == nil)
    }

    @Test("HUD own arrow follows measured heading and route tangent in overview and focus")
    func ownArrowProjectionTracksHeadingAndTangentInBothCameras() throws {
        #expect(NavigationHUDAngle.shortestDelta(from: 359, to: 1) == 2)
        #expect(NavigationHUDAngle.shortestDelta(from: 1, to: 359) == -2)

        let route = (0...8).map { index in
            CLLocationCoordinate2D(latitude: 0, longitude: Double(index) * 0.005)
        }
        let user = CLLocationCoordinate2D(latitude: 0, longitude: 0.015)
        let overview = NavigationHUDProjection.project(
            routeCoordinates: route,
            userCoordinate: user,
            remoteCoordinate: nil,
            size: CGSize(width: 390, height: 760),
            headingDegrees: 0
        )
        let north = try #require(overview.userHeadingVector)
        #expect(abs(north.dx) < 2)
        #expect(north.dy < 0)

        let overviewTangent = NavigationHUDProjection.project(
            routeCoordinates: route,
            userCoordinate: user,
            remoteCoordinate: nil,
            size: CGSize(width: 390, height: 760)
        )
        let east = try #require(overviewTangent.userHeadingVector)
        #expect(east.dx > 0)
        #expect(abs(east.dy) < 2)

        let focusedRoute = NavigationHUDFocusRoute.coordinates(route: route, userCoordinate: user)
        let focusedEast = NavigationHUDProjection.project(
            routeCoordinates: focusedRoute,
            userCoordinate: user,
            remoteCoordinate: nil,
            size: CGSize(width: 760, height: 390),
            alignForward: true,
            headingDegrees: 90
        )
        let ahead = try #require(focusedEast.userHeadingVector)
        #expect(ahead.dy < 0)

        let focusedNorth = NavigationHUDProjection.project(
            routeCoordinates: focusedRoute,
            userCoordinate: user,
            remoteCoordinate: nil,
            size: CGSize(width: 760, height: 390),
            alignForward: true,
            headingDegrees: 0
        )
        let left = try #require(focusedNorth.userHeadingVector)
        #expect(left.dx < 0)

        let noHeadingNoFallback = NavigationHUDProjection.project(
            routeCoordinates: route,
            userCoordinate: user,
            remoteCoordinate: nil,
            size: CGSize(width: 390, height: 760),
            allowsRouteTangentFallback: false
        )
        #expect(noHeadingNoFallback.userHeadingVector == nil)
    }

    @Test("Settings search explains the active tracking prerequisite before permission")
    func searchPrerequisiteCopyDistinguishesTrackingSwitchFromPermission() throws {
        let entry = try #require(SettingsSearchIndex.entries().first {
            $0.key == "smart_frequent_background_speed_threshold_title"
        })

        #expect(SettingsSearchIndex.prerequisiteMessageKey(
            for: entry,
            trackingEnabled: false,
            trackingReady: false
        ) == "settings_search_requires_parent_setting")
        #expect(SettingsSearchIndex.prerequisiteMessageKey(
            for: entry,
            trackingEnabled: true,
            trackingReady: false
        ) == "settings_search_requires_tracking_permission")
    }
}
