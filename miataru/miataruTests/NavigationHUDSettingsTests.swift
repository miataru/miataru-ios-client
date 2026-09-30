import Testing
import Foundation
import CoreLocation
@testable import miataru

struct NavigationHUDSettingsTests {
    @Test("Own-device speed formats fresh locations in km/h and rejects stale or invalid values")
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

        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: location(speed: 10, age: 0), now: now) == "36")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: location(speed: 10, age: 15), now: now) == "36")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: location(speed: 10, age: 15.01), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: location(speed: 10, age: -0.01), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: location(speed: -1, age: 0), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: nil, now: now) == nil)
    }

    @Test("Navigation speed uses tracked server samples for five minutes and hides invalid responses")
    func trackedServerSpeedValidityAndInvalidation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(speed: Double?, age: TimeInterval) -> NavigationHUDServerSpeedSample {
            NavigationHUDServerSpeedSample(metersPerSecond: speed, timestamp: now.addingTimeInterval(-age))
        }

        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: 10, age: 0), now: now) == "36")
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: 0, age: 300), now: now) == "0")
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: 10, age: 300.01), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: 10, age: -0.01), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: nil, age: 0), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: sample(speed: -.infinity, age: 0), now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: nil, now: now) == nil)
    }

    @Test("Successful server responses replace or clear tracked speed samples")
    func successfulServerResponseReplacesPreviousSpeed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = NavigationHUDSpeedPolicy.sampleFromSuccessfulResponse(
            metersPerSecond: 10,
            timestamp: now
        )
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: previous, now: now) == "36")

        let missingSpeedResponse = NavigationHUDSpeedPolicy.sampleFromSuccessfulResponse(
            metersPerSecond: nil,
            timestamp: now.addingTimeInterval(1)
        )
        #expect(missingSpeedResponse == nil)
        #expect(NavigationHUDSpeedPolicy.formattedTrackedDeviceSpeed(for: missingSpeedResponse, now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.sampleFromSuccessfulResponse(
            metersPerSecond: -.infinity,
            timestamp: now
        ) == nil)
    }

    @Test("Navigation speed direction selects only its own source")
    func speedSourceFollowsNavigationDirection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let remote = NavigationHUDServerSpeedSample(metersPerSecond: 10, timestamp: now)
        let own = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 5,
            timestamp: now
        )

        #expect(NavigationHUDSpeedPolicy.formattedSpeed(
            isDeviceToUser: true,
            trackedSample: remote,
            ownLocations: [own],
            retainedOwnSample: NavigationHUDOwnSpeedSample(metersPerSecond: 5, timestamp: now),
            now: now
        ) == "36")
        #expect(NavigationHUDSpeedPolicy.formattedSpeed(
            isDeviceToUser: false,
            trackedSample: remote,
            ownLocations: [own],
            now: now
        ) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedSpeed(
            isDeviceToUser: true,
            trackedSample: nil,
            ownLocations: [own],
            retainedOwnSample: NavigationHUDOwnSpeedSample(metersPerSecond: 5, timestamp: now),
            now: now
        ) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedSpeed(
            isDeviceToUser: false,
            trackedSample: remote,
            ownLocations: [nil],
            now: now
        ) == nil)
    }

    @Test("Own device speed selects the newest valid candidate within fifteen seconds")
    func ownDeviceSpeedChoosesNewestFreshValidCandidate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let freshStoppedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 0,
            timestamp: now.addingTimeInterval(-15)
        )
        let staleLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 0,
            timestamp: now.addingTimeInterval(-15.01)
        )
        let invalidSpeedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: -1,
            timestamp: now.addingTimeInterval(-1)
        )
        let validCurrentLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 5,
            timestamp: now.addingTimeInterval(-2)
        )
        let newerValidRawLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 10,
            timestamp: now.addingTimeInterval(-1)
        )
        let futureLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52, longitude: 13),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 20,
            timestamp: now.addingTimeInterval(1)
        )

        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: freshStoppedLocation, now: now) == "0")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(for: staleLocation, now: now) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(from: [invalidSpeedLocation, validCurrentLocation], now: now) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(from: [validCurrentLocation, newerValidRawLocation], now: now) == "36")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(from: [staleLocation, validCurrentLocation], now: now) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(from: [futureLocation, validCurrentLocation], now: now) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(from: [invalidSpeedLocation, staleLocation, futureLocation], now: now) == nil)
    }

    @Test("Own-device speed keeps the last fresh valid sample when later callbacks have invalid speed")
    func ownDeviceSpeedRetainsFreshSampleAcrossInvalidCallbacks() {
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

        let priorValid = location(speed: 5, age: 2)
        let currentSample = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: nil,
            from: priorValid,
            now: now
        )
        let invalidAcceptedUpdate = location(speed: -1, age: 1)
        let afterInvalidUpdate = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: currentSample,
            from: invalidAcceptedUpdate,
            now: now
        )

        #expect(afterInvalidUpdate == currentSample)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [invalidAcceptedUpdate],
            retainedSample: afterInvalidUpdate,
            now: now
        ) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [invalidAcceptedUpdate],
            retainedSample: afterInvalidUpdate,
            now: now.addingTimeInterval(13)
        ) == "18")
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [invalidAcceptedUpdate],
            retainedSample: afterInvalidUpdate,
            now: now.addingTimeInterval(13.01)
        ) == nil)
    }

    @Test("A newer valid own-speed sample replaces the cached value and zero remains valid")
    func newerOwnSpeedSampleReplacesOldAndZeroIsValid() {
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

        let oldSample = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: nil,
            from: location(speed: 5, age: 3),
            now: now
        )
        let newerMovingSample = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: oldSample,
            from: location(speed: 10, age: 2),
            now: now
        )
        let newerStoppedSample = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: newerMovingSample,
            from: location(speed: 0, age: 1),
            now: now
        )

        #expect(newerMovingSample?.metersPerSecond == 10)
        #expect(newerStoppedSample?.metersPerSecond == 0)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [],
            retainedSample: newerStoppedSample,
            now: now
        ) == "0")
    }

    @Test("Own-device speed cache ignores stale, future, and out-of-order observations")
    func ownDeviceSpeedSampleRejectsStaleFutureAndOutOfOrderUpdates() {
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
        let current = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: nil,
            from: location(speed: 10, age: 2),
            now: now
        )
        let stale = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: current,
            from: location(speed: 20, age: 15.01),
            now: now
        )
        let future = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: current,
            from: location(speed: 20, age: -0.01),
            now: now
        )
        let outOfOrder = NavigationHUDSpeedPolicy.updatingOwnDeviceSpeedSample(
            currentSample: current,
            from: location(speed: 20, age: 3),
            now: now
        )

        #expect(stale == current)
        #expect(future == current)
        #expect(outOfOrder == current)
    }

    @Test("Own-device speed uses sample time rather than a delayed one-second display tick")
    func ownDeviceSpeedDoesNotRejectSampleNewerThanPreviousDisplayTick() {
        let sampleTimestamp = Date(timeIntervalSince1970: 1_800_000_001)
        let sample = NavigationHUDOwnSpeedSample(metersPerSecond: 10, timestamp: sampleTimestamp)
        let previousDisplayTick = sampleTimestamp.addingTimeInterval(-0.25)

        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [],
            retainedSample: sample,
            now: previousDisplayTick
        ) == nil)
        #expect(NavigationHUDSpeedPolicy.formattedOwnDeviceSpeed(
            from: [],
            retainedSample: sample,
            now: sampleTimestamp.addingTimeInterval(0.25)
        ) == "36")
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
