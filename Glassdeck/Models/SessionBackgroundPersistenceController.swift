#if canImport(UIKit)
@preconcurrency import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class SessionBackgroundPersistenceController: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let locationManager: CLLocationManager
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var featureEnabled = false
    private var hasLiveSessions = false

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isLocationServicesEnabled: Bool
    private(set) var isRuntimeActive = false
    private(set) var statusMessage = "Background persistence is off."

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        self.authorizationStatus = locationManager.authorizationStatus
        self.isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.activityType = .other
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.locationManager.distanceFilter = kCLDistanceFilterNone
        self.locationManager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationDescription: String {
        guard isLocationServicesEnabled else {
            return "Location Services are disabled system-wide."
        }

        switch authorizationStatus {
        case .authorizedAlways:
            return "Location access is allowed at all times."
        case .authorizedWhenInUse:
            return "Location access is allowed while Glassdeck is in use."
        case .notDetermined:
            return "Location permission has not been requested yet."
        case .denied:
            return "Location permission is denied."
        case .restricted:
            return "Location access is restricted on this device."
        @unknown default:
            return "Location authorization state is unavailable."
        }
    }

    func setFeatureEnabled(_ enabled: Bool) {
        featureEnabled = enabled
        syncRuntime(requestAuthorizationIfNeeded: enabled)
    }

    func setHasLiveSessions(_ hasLiveSessions: Bool) {
        self.hasLiveSessions = hasLiveSessions
        syncRuntime()
    }

    func resumeIfNeeded() {
        syncRuntime()
    }

    func requestAuthorizationIfNeeded() {
        syncRuntime(requestAuthorizationIfNeeded: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        syncRuntime()
    }

    private func syncRuntime(requestAuthorizationIfNeeded: Bool = false) {
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
        authorizationStatus = locationManager.authorizationStatus

        guard featureEnabled else {
            stopRuntime(message: "Background persistence is off.")
            return
        }

        guard hasLiveSessions else {
            stopRuntime(message: "Background persistence will resume when a live session exists.")
            return
        }

        guard isLocationServicesEnabled else {
            stopRuntime(message: "Enable Location Services to keep sessions alive in the background.")
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            if requestAuthorizationIfNeeded {
                statusMessage = "Requesting location permission for background persistence…"
                locationManager.requestWhenInUseAuthorization()
            } else {
                statusMessage = "Location permission is required to enable background persistence."
            }
        case .denied:
            stopRuntime(message: "Location permission is denied. Enable it in Settings to keep sessions alive in the background.")
        case .restricted:
            stopRuntime(message: "Location access is restricted on this device.")
        case .authorizedWhenInUse, .authorizedAlways:
            startRuntimeIfNeeded()
        @unknown default:
            stopRuntime(message: "Location authorization is unavailable.")
        }
    }

    private func startRuntimeIfNeeded() {
        guard !isRuntimeActive else {
            statusMessage = "Background persistence is active while sessions are live."
            return
        }

        locationManager.allowsBackgroundLocationUpdates = true
        backgroundActivitySession = CLBackgroundActivitySession()
        locationManager.startUpdatingLocation()
        isRuntimeActive = true
        statusMessage = "Background persistence is active while sessions are live."
    }

    private func stopRuntime(message: String) {
        locationManager.stopUpdatingLocation()
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        isRuntimeActive = false
        statusMessage = message
    }
}
#endif
