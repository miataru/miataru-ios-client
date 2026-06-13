import CoreLocation
import Testing
import UIKit
@testable import miataru

@Suite("Smart frequent background policy tests")
struct SmartFrequentBackgroundPolicyTests {
    @Test("Smart frequent speed detection supports hybrid and GPS-only modes")
    func smartFrequentSpeedDetectionSupportsHybridAndGPSOnlyModes() {
        let previous = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let current = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.5290, longitude: 13.4050),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 1_300)
        )
        let gpsSpeed = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.5290, longitude: 13.4050),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: 4,
            timestamp: Date(timeIntervalSince1970: 1_300)
        )

        let derivedSpeed = SmartFrequentBackgroundPolicy.speedKmh(
            for: current,
            previousLocation: previous,
            detectionMode: .hybrid
        )
        #expect((derivedSpeed ?? 0) > 10)
        #expect(SmartFrequentBackgroundPolicy.speedKmh(
            for: current,
            previousLocation: previous,
            detectionMode: .gpsOnly
        ) == nil)
        let gpsSpeedKmh = SmartFrequentBackgroundPolicy.speedKmh(
            for: gpsSpeed,
            previousLocation: previous,
            detectionMode: .hybrid
        )
        #expect(abs((gpsSpeedKmh ?? 0) - 14.4) < 0.001)
    }

    @Test("Persisted smart frequent seed is fresh-gated and still rejects implausible activation")
    func persistedSmartFrequentSeedIsFreshGatedAndRejectsImplausibleActivation() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let seedTimestamp = now.addingTimeInterval(-60)
        let seed = try #require(SmartFrequentBackgroundPolicy.seedLocation(
            latitude: 52.5200,
            longitude: 13.4050,
            altitude: 34,
            horizontalAccuracy: 12,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: seedTimestamp,
            now: now,
            inactivityWindow: 600
        ))

        #expect(SmartFrequentBackgroundPolicy.seedLocation(
            latitude: 52.5200,
            longitude: 13.4050,
            altitude: 34,
            horizontalAccuracy: 12,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: now.addingTimeInterval(-600),
            now: now,
            inactivityWindow: 600
        ) == nil)
        #expect(SmartFrequentBackgroundPolicy.seedLocation(
            latitude: 52.5200,
            longitude: 13.4050,
            altitude: 34,
            horizontalAccuracy: 12,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: now.addingTimeInterval(1),
            now: now,
            inactivityWindow: 600
        ) == nil)

        let plausibleMovement = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.5218, longitude: 13.4050),
            altitude: 34,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: now
        )
        let plausibleSpeed = SmartFrequentBackgroundPolicy.speedKmh(
            for: plausibleMovement,
            previousLocation: seed,
            detectionMode: .hybrid
        )
        #expect(SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: plausibleMovement.timestamp,
            previousLocationUpdateAt: seed.timestamp,
            inactivityWindow: 600
        ))
        #expect(SmartFrequentBackgroundPolicy.shouldActivate(
            speedKmh: plausibleSpeed,
            thresholdKmh: 10
        ))

        let implausibleMovement = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.5200, longitude: 13.4050),
            altitude: 34,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            speed: -1,
            timestamp: now
        )
        let implausibleSpeed = SmartFrequentBackgroundPolicy.speedKmh(
            for: implausibleMovement,
            previousLocation: seed,
            detectionMode: .hybrid
        )
        #expect((implausibleSpeed ?? 0) > 200)
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(
            speedKmh: implausibleSpeed,
            thresholdKmh: 2
        ))
    }

    @Test("Smart frequent activation evidence is quality aware and startup guarded")
    func smartFrequentActivationEvidenceIsQualityAwareAndStartupGuarded() throws {
        let firstStationary = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8191, longitude: 10.8078),
            altitude: 0,
            horizontalAccuracy: 18.2,
            verticalAccuracy: 5,
            course: -1,
            speed: 0,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let speedOnlyStationary = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8191, longitude: 10.8078),
            altitude: 0,
            horizontalAccuracy: 17.9,
            verticalAccuracy: 5,
            course: -1,
            speed: 1.001774549484253,
            timestamp: Date(timeIntervalSince1970: 1_003)
        )

        let startupSpeedOnlyEvidence = SmartFrequentBackgroundPolicy.activationEvidence(
            for: speedOnlyStationary,
            previousLocation: firstStationary,
            detectionMode: .hybrid,
            thresholdKmh: 2,
            frequentDistanceFilterMeters: 10,
            isStartupBatch: true
        )
        #expect(startupSpeedOnlyEvidence.kind == .insufficient)

        let previousWalking = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8193, longitude: 10.8020),
            altitude: 0,
            horizontalAccuracy: 2.1,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 2_000)
        )
        let currentWalking = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8174, longitude: 10.7958),
            altitude: 0,
            horizontalAccuracy: 2.3,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 2_411)
        )
        let walkingEvidence = SmartFrequentBackgroundPolicy.activationEvidence(
            for: currentWalking,
            previousLocation: previousWalking,
            detectionMode: .hybrid,
            thresholdKmh: 2,
            frequentDistanceFilterMeters: 10,
            isStartupBatch: true
        )
        #expect(walkingEvidence.kind == .trustedDerivedSpeed)
        #expect((walkingEvidence.distanceMeters ?? 0) > 450)

        let sameSecondSpike = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8190, longitude: 10.8077),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 3_000.2)
        )
        let spikeAnchor = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.8190, longitude: 10.8076),
            altitude: 0,
            horizontalAccuracy: 11.4,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 3_000)
        )
        let spikeEvidence = SmartFrequentBackgroundPolicy.activationEvidence(
            for: sameSecondSpike,
            previousLocation: spikeAnchor,
            detectionMode: .hybrid,
            thresholdKmh: 2,
            frequentDistanceFilterMeters: 10,
            isStartupBatch: true
        )
        #expect(spikeEvidence.kind == .insufficient)

        let regionEvidence = SmartFrequentBackgroundPolicy.activationEvidence(
            for: speedOnlyStationary,
            previousLocation: firstStationary,
            detectionMode: .hybrid,
            thresholdKmh: 30,
            frequentDistanceFilterMeters: 10,
            isStartupBatch: true,
            regionExitRadiusMeters: 150
        )
        #expect(regionEvidence.kind == .regionExit)
    }

    @Test("Smart frequent exit fence eligibility and radius are automatic")
    func smartFrequentExitFenceEligibilityAndRadiusAreAutomatic() {
        #expect(SmartFrequentBackgroundPolicy.exitFenceRadius(
            frequentDistanceFilterMeters: 10,
            maximumRegionMonitoringDistance: 1_000
        ) == 150)
        #expect(SmartFrequentBackgroundPolicy.exitFenceRadius(
            frequentDistanceFilterMeters: 100,
            maximumRegionMonitoringDistance: 120
        ) == 120)

        #expect(SmartFrequentBackgroundPolicy.shouldMaintainExitFence(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            smartEnabled: true,
            manualFrequentEnabled: false,
            smartRuntimeActive: false,
            regionMonitoringAvailable: true
        ))
        #expect(!SmartFrequentBackgroundPolicy.shouldMaintainExitFence(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            smartEnabled: true,
            manualFrequentEnabled: true,
            smartRuntimeActive: false,
            regionMonitoringAvailable: true
        ))
        #expect(SmartFrequentBackgroundPolicy.shouldMaintainExitFence(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            smartEnabled: true,
            manualFrequentEnabled: false,
            smartRuntimeActive: true,
            regionMonitoringAvailable: true
        ))
    }

    @Test("Smart frequent activation and inactivity policies are threshold based")
    func smartFrequentActivationAndInactivityPoliciesAreThresholdBased() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 10, thresholdKmh: 10))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 9.9, thresholdKmh: 10))
        #expect(SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 2, thresholdKmh: 2))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 1.9, thresholdKmh: 2))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: nil, thresholdKmh: 10))
        #expect(SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 200, thresholdKmh: 10))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 200.1, thresholdKmh: 10))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: -1, thresholdKmh: 10))
        #expect(!SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: .infinity, thresholdKmh: 10))
        #expect(SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-599),
            previousLocationUpdateAt: now.addingTimeInterval(-599),
            inactivityWindow: 600
        ))
        #expect(!SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-1),
            previousLocationUpdateAt: nil,
            inactivityWindow: 600
        ))
        #expect(!SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-600),
            previousLocationUpdateAt: now.addingTimeInterval(-1),
            inactivityWindow: 600
        ))
        #expect(!SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-1),
            previousLocationUpdateAt: now.addingTimeInterval(-600),
            inactivityWindow: 600
        ))
        #expect(SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-1),
            previousLocationUpdateAt: nil,
            inactivityWindow: 600,
            evidenceKind: .trustedGPSSpeed
        ))
        #expect(SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: now.addingTimeInterval(-1),
            previousLocationUpdateAt: now.addingTimeInterval(-600),
            inactivityWindow: 600,
            evidenceKind: .trustedGPSSpeed
        ))

        #expect(!SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-600),
            lastRelevantMovementAt: now,
            inactivityWindow: 600
        ))
        #expect(SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: now,
            lastRelevantMovementAt: now.addingTimeInterval(-601),
            inactivityWindow: 600
        ))
        #expect(!SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-599),
            lastRelevantMovementAt: now.addingTimeInterval(-599),
            inactivityWindow: 600
        ))
        #expect(SmartFrequentBackgroundPolicy.nextInactivityTimeout(
            lastLocationUpdateAt: now,
            lastRelevantMovementAt: now.addingTimeInterval(-100),
            inactivityWindow: 600
        ) == now.addingTimeInterval(500))

        let anchor = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: 10.0),
            altitude: 0,
            horizontalAccuracy: 4,
            verticalAccuracy: -1,
            course: -1,
            speed: -1,
            timestamp: now
        )
        let candidate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 49.0001, longitude: 10.0),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: -1,
            course: -1,
            speed: -1,
            timestamp: now.addingTimeInterval(10)
        )
        #expect(SmartFrequentBackgroundPolicy.movementDistanceThreshold(
            frequentDistanceFilterMeters: 10,
            from: anchor,
            to: candidate
        ) == 12)
        #expect(SmartFrequentBackgroundPolicy.shouldConfirmMovement(
            distanceMeters: 12,
            thresholdMeters: 12
        ))
        #expect(!SmartFrequentBackgroundPolicy.shouldConfirmMovement(
            distanceMeters: 11.9,
            thresholdMeters: 12
        ))
    }

    @Test("Smart frequent inactivity timer action avoids stale callback recursion")
    func smartFrequentInactivityTimerActionAvoidsStaleCallbackRecursion() {
        let now = Date(timeIntervalSince1970: 20_000)
        let inactivityWindow: TimeInterval = 600

        #expect(SmartFrequentBackgroundPolicy.inactivityTimerAction(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-inactivityWindow - 1),
            lastRelevantMovementAt: now.addingTimeInterval(-inactivityWindow - 1),
            inactivityWindow: inactivityWindow
        ) == .none)

        #expect(SmartFrequentBackgroundPolicy.inactivityTimerAction(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-10),
            lastRelevantMovementAt: now.addingTimeInterval(-inactivityWindow - 1),
            inactivityWindow: inactivityWindow
        ) == .expired)

        #expect(SmartFrequentBackgroundPolicy.inactivityTimerAction(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-10),
            lastRelevantMovementAt: now.addingTimeInterval(-100),
            inactivityWindow: inactivityWindow
        ) == .schedule(now.addingTimeInterval(500)))

        #expect(SmartFrequentBackgroundPolicy.inactivityTimerAction(
            now: now,
            lastLocationUpdateAt: nil,
            lastRelevantMovementAt: now.addingTimeInterval(-100),
            inactivityWindow: inactivityWindow
        ) == .none)

        #expect(SmartFrequentBackgroundPolicy.inactivityTimerAction(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-10),
            lastRelevantMovementAt: nil,
            inactivityWindow: inactivityWindow
        ) == .none)
    }

    @Test("Smart frequent runtime watchdog recovers active callback gaps")
    func smartFrequentRuntimeWatchdogRecoversActiveCallbackGaps() {
        let now = Date(timeIntervalSince1970: 20_000)
        let inactivityWindow: TimeInterval = 600

        #expect(!SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-inactivityWindow - 1),
            lastRelevantMovementAt: now.addingTimeInterval(-inactivityWindow - 1),
            inactivityWindow: inactivityWindow
        ))
        #expect(SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: now.addingTimeInterval(-10),
            lastRelevantMovementAt: now.addingTimeInterval(-inactivityWindow - 1),
            inactivityWindow: inactivityWindow
        ))

        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .probing,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: nil,
            runtimeStartedAt: now.addingTimeInterval(-SmartFrequentBackgroundPolicy.runtimeWatchdogInterval - 1),
            recoveryAttemptCount: 0,
            now: now
        ) == .reassert)
        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .confirmedActive,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: now.addingTimeInterval(-SmartFrequentBackgroundPolicy.runtimeWatchdogInterval - 1),
            runtimeStartedAt: now.addingTimeInterval(-200),
            recoveryAttemptCount: 0,
            now: now
        ) == .reassert)
        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .confirmedActive,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: now.addingTimeInterval(-10),
            runtimeStartedAt: now.addingTimeInterval(-200),
            recoveryAttemptCount: 1,
            now: now
        ) == .wait)
        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .confirmedActive,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: now.addingTimeInterval(-10),
            runtimeStartedAt: now.addingTimeInterval(-200),
            recoveryAttemptCount: SmartFrequentBackgroundPolicy.maximumRuntimeRecoveryAttempts,
            now: now
        ) == .wait)
        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .confirmedActive,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: now.addingTimeInterval(-SmartFrequentBackgroundPolicy.runtimeWatchdogInterval - 1),
            runtimeStartedAt: now.addingTimeInterval(-200),
            recoveryAttemptCount: SmartFrequentBackgroundPolicy.maximumRuntimeRecoveryAttempts,
            now: now
        ) == .deactivate)
        #expect(SmartFrequentBackgroundPolicy.watchdogAction(
            phase: .waiting,
            smartEnabled: true,
            manualFrequentEnabled: false,
            lastFrequentCallbackAt: nil,
            runtimeStartedAt: now.addingTimeInterval(-200),
            recoveryAttemptCount: 0,
            now: now
        ) == .ignore)
    }

    @Test("Smart frequent recovery diagnostics context includes watchdog timing")
    func smartFrequentRecoveryDiagnosticsContextIncludesWatchdogTiming() {
        let now = Date(timeIntervalSince1970: 20_000)
        let lastFrequentCallbackAt = now.addingTimeInterval(-120)
        let lastBackgroundUploadAt = now.addingTimeInterval(-240)
        let watchdogReference = now.addingTimeInterval(-300)
        let formatter = ISO8601DateFormatter()

        let context = SmartFrequentBackgroundPolicy.recoveryDiagnosticsContext(
            now: now,
            recoveryAttemptCount: 2,
            maximumRecoveryAttempts: 3,
            phase: .confirmedActive,
            frequentManagerAllowsBackground: true,
            frequentManagerShowsIndicator: false,
            frequentStandardUpdatesActive: true,
            frequentActivitySessionActive: true,
            lastFrequentCallbackAt: lastFrequentCallbackAt,
            lastBackgroundUploadAt: lastBackgroundUploadAt,
            runtimeStartedAt: now.addingTimeInterval(-500),
            lastRelevantMovementAt: now.addingTimeInterval(-600),
            watchdogReference: watchdogReference
        )

        #expect(context["attempt"] == .integer(2))
        #expect(context["recoveryAttemptCount"] == .integer(2))
        #expect(context["maximumAttempts"] == .integer(3))
        #expect(context["maximumRecoveryAttempts"] == .integer(3))
        #expect(context["phase"] == .string("confirmedActive"))
        #expect(context["frequentManagerAllowsBackground"] == .bool(true))
        #expect(context["frequentManagerShowsIndicator"] == .bool(false))
        #expect(context["frequentStandardUpdatesActive"] == .bool(true))
        #expect(context["frequentActivitySessionActive"] == .bool(true))
        #expect(context["lastFrequentCallbackAt"] == .string(formatter.string(from: lastFrequentCallbackAt)))
        #expect(context["lastFrequentCallbackAgeSeconds"] == .double(120))
        #expect(context["lastBackgroundUploadAt"] == .string(formatter.string(from: lastBackgroundUploadAt)))
        #expect(context["lastBackgroundUploadAgeSeconds"] == .double(240))
        #expect(context["watchdogReferenceAt"] == .string(formatter.string(from: watchdogReference)))
        #expect(context["secondsSinceWatchdogReference"] == .double(300))
    }

    @Test("Smart frequent runtime is evaluated only in background")
    func smartFrequentRuntimeIsEvaluatedOnlyInBackground() {
        #expect(LocationTrackingPolicy.shouldEvaluateSmartFrequentRuntime(applicationState: .background))
        #expect(!LocationTrackingPolicy.shouldEvaluateSmartFrequentRuntime(applicationState: .inactive))
        #expect(!LocationTrackingPolicy.shouldEvaluateSmartFrequentRuntime(applicationState: .active))
    }

    @Test("Smart frequent confirmed runtime marker persists, consumes, and rejects non-confirmed phases")
    func smartFrequentConfirmedRuntimeMarkerPersistsConsumesAndRejectsNonConfirmedPhases() throws {
        let suiteName = "SmartFrequentRuntimeMarkerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SmartFrequentBackgroundRuntimeMarkerStore(defaults: defaults)
        let confirmedAt = Date(timeIntervalSince1970: 10_000)
        let movementAt = confirmedAt.addingTimeInterval(-30)
        let confirmedMarker = SmartFrequentBackgroundRuntimeMarker(
            phase: .confirmedActive,
            confirmedAt: confirmedAt,
            lastRelevantMovementAt: movementAt,
            activationNotificationDelivered: true
        )

        store.save(confirmedMarker)
        #expect(store.load() == confirmedMarker)
        #expect(store.consume() == confirmedMarker)
        #expect(store.load() == nil)

        store.save(SmartFrequentBackgroundRuntimeMarker(
            phase: .probing,
            confirmedAt: confirmedAt,
            lastRelevantMovementAt: movementAt,
            activationNotificationDelivered: true
        ))
        #expect(store.load() == nil)

        store.save(confirmedMarker)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Smart frequent restart recovery resumes only fresh confirmed runtime markers")
    func smartFrequentRestartRecoveryResumesOnlyFreshConfirmedRuntimeMarkers() {
        let now = Date(timeIntervalSince1970: 20_000)
        let inactivityWindow: TimeInterval = 600
        let freshMarker = SmartFrequentBackgroundRuntimeMarker(
            phase: .confirmedActive,
            confirmedAt: now.addingTimeInterval(-1_200),
            lastRelevantMovementAt: now.addingTimeInterval(-30),
            activationNotificationDelivered: true
        )

        #expect(SmartFrequentBackgroundPolicy.runtimeMarkerReferenceDate(freshMarker) == freshMarker.lastRelevantMovementAt)
        #expect(SmartFrequentBackgroundPolicy.isRuntimeMarkerFresh(
            freshMarker,
            now: now,
            inactivityWindow: inactivityWindow
        ))
        #expect(SmartFrequentBackgroundPolicy.restartRecoveryAction(
            marker: freshMarker,
            now: now,
            inactivityWindow: inactivityWindow,
            smartEnabled: true,
            manualFrequentEnabled: false,
            authorizationStatus: .authorizedAlways,
            trackAndReportLocation: true,
            isTracking: true,
            deviceKeyAuthBlocked: false,
            modeChangeNotificationsEnabled: true
        ) == .resume)

        let staleMarker = SmartFrequentBackgroundRuntimeMarker(
            phase: .confirmedActive,
            confirmedAt: now.addingTimeInterval(-1_200),
            lastRelevantMovementAt: now.addingTimeInterval(-inactivityWindow - 1),
            activationNotificationDelivered: true
        )

        #expect(!SmartFrequentBackgroundPolicy.isRuntimeMarkerFresh(
            staleMarker,
            now: now,
            inactivityWindow: inactivityWindow
        ))
        #expect(SmartFrequentBackgroundPolicy.restartRecoveryAction(
            marker: staleMarker,
            now: now,
            inactivityWindow: inactivityWindow,
            smartEnabled: true,
            manualFrequentEnabled: false,
            authorizationStatus: .authorizedAlways,
            trackAndReportLocation: true,
            isTracking: true,
            deviceKeyAuthBlocked: false,
            modeChangeNotificationsEnabled: true
        ) == .notifyDeactivation)
        #expect(SmartFrequentBackgroundPolicy.restartRecoveryAction(
            marker: freshMarker,
            now: now,
            inactivityWindow: inactivityWindow,
            smartEnabled: true,
            manualFrequentEnabled: true,
            authorizationStatus: .authorizedAlways,
            trackAndReportLocation: true,
            isTracking: true,
            deviceKeyAuthBlocked: false,
            modeChangeNotificationsEnabled: true
        ) == .ignore)
    }

    @Test("Smart frequent exit fence anchor uses newest usable location")
    func smartFrequentExitFenceAnchorUsesNewestUsableLocation() throws {
        func location(timestamp: TimeInterval, accuracy: Double, latitude: Double = 49.8190) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 10.8077),
                altitude: 0,
                horizontalAccuracy: accuracy,
                verticalAccuracy: 5,
                course: -1,
                speed: -1,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        }

        let olderRaw = location(timestamp: 100, accuracy: 3)
        let current = location(timestamp: 200, accuracy: 25)
        let smartReference = location(timestamp: 150, accuracy: 7)
        let tooInaccurate = location(timestamp: 300, accuracy: 500)

        let anchor = try #require(SmartFrequentBackgroundPolicy.newestExitFenceAnchor(from: [
            olderRaw,
            current,
            smartReference,
            tooInaccurate
        ]))
        #expect(anchor.timestamp == current.timestamp)

        let worseSameTimestamp = location(timestamp: 400, accuracy: 30)
        let betterSameTimestamp = location(timestamp: 400, accuracy: 5, latitude: 49.8200)
        let sameTimestampAnchor = try #require(SmartFrequentBackgroundPolicy.newestExitFenceAnchor(from: [
            worseSameTimestamp,
            betterSameTimestamp
        ]))
        #expect(sameTimestampAnchor.coordinate.latitude == betterSameTimestamp.coordinate.latitude)
    }
}
