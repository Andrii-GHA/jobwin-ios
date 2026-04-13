import CoreLocation
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private static let wantsSharingKey = "jobwin.location.wantsSharing"

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var lastSentSnapshot: DeviceLocationSnapshot?
    @ObservationIgnored private var isSendingUpdate = false

    var authorizationStatus: CLAuthorizationStatus
    var sharingState: LocationSharingState = .idle
    var wantsSharing: Bool
    var lastSnapshot: DeviceLocationSnapshot?
    var lastSentAt: Date?
    var latestErrorMessage: String?

    override init() {
        let storedWantsSharing = UserDefaults.standard.bool(forKey: Self.wantsSharingKey)
        self.authorizationStatus = .notDetermined
        self.wantsSharing = storedWantsSharing
        super.init()

        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25

        updateAuthorization(manager.authorizationStatus)
    }

    func configure(using sessionStore: SessionStore) {
        client = sessionStore.makeAPIClient()

        if wantsSharing {
            startManagerIfPossible()
        }
    }

    func clearSession() {
        client = nil
        manager.stopUpdatingLocation()
        lastSnapshot = nil
        lastSentSnapshot = nil
        lastSentAt = nil
        latestErrorMessage = nil
        sharingState = wantsSharing ? .paused : .idle
    }

    func resetAfterSignOut() {
        wantsSharing = false
        UserDefaults.standard.set(false, forKey: Self.wantsSharingKey)
        clearSession()
        sharingState = .idle
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard wantsSharing else { return }

        switch phase {
        case .active:
            startManagerIfPossible()
        case .inactive, .background:
            manager.stopUpdatingLocation()
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                sharingState = .paused
            }
        @unknown default:
            break
        }
    }

    func startSharing(using sessionStore: SessionStore) async {
        client = sessionStore.makeAPIClient()
        latestErrorMessage = nil
        wantsSharing = true
        UserDefaults.standard.set(true, forKey: Self.wantsSharingKey)

        guard CLLocationManager.locationServicesEnabled() else {
            sharingState = .blocked
            latestErrorMessage = "Location services are disabled on this device."
            return
        }

        if authorizationStatus == .notDetermined {
            sharingState = .requestingPermission
            manager.requestWhenInUseAuthorization()
            return
        }

        startManagerIfPossible()
    }

    func stopSharing() async {
        wantsSharing = false
        UserDefaults.standard.set(false, forKey: Self.wantsSharingKey)
        manager.stopUpdatingLocation()
        lastSentSnapshot = nil
        lastSentAt = nil
        sharingState = .idle

        guard let client else { return }

        do {
            let _: MobileLocationStopResponseDTO = try await client.delete(MobileAPI.location)
            latestErrorMessage = nil
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization(manager.authorizationStatus)

        if wantsSharing {
            startManagerIfPossible()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsSharing, let location = locations.last else { return }

        let snapshot = DeviceLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            headingDegrees: location.course >= 0 ? location.course : nil,
            speedMps: location.speed >= 0 ? location.speed : nil,
            capturedAt: location.timestamp
        )

        lastSnapshot = snapshot

        guard shouldSend(snapshot: snapshot) else { return }
        Task {
            await send(snapshot: snapshot)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        latestErrorMessage = error.localizedDescription
    }

    private func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if wantsSharing {
                sharingState = .active
            } else {
                sharingState = .idle
            }
        case .notDetermined:
            sharingState = wantsSharing ? .requestingPermission : .idle
        case .restricted, .denied:
            sharingState = .blocked
        @unknown default:
            sharingState = .blocked
        }
    }

    private func startManagerIfPossible() {
        guard wantsSharing else { return }
        guard client != nil else {
            sharingState = .paused
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            sharingState = .blocked
            latestErrorMessage = "Location services are disabled on this device."
            return
        }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            sharingState = .active
        case .notDetermined:
            sharingState = .requestingPermission
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            sharingState = .blocked
            latestErrorMessage = "Location permission is blocked."
        @unknown default:
            sharingState = .blocked
            latestErrorMessage = "Location permission is unavailable."
        }
    }

    private func shouldSend(snapshot: DeviceLocationSnapshot) -> Bool {
        guard let previous = lastSentSnapshot else { return true }

        let elapsed = snapshot.capturedAt.timeIntervalSince(previous.capturedAt)
        let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let nextLocation = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let distance = nextLocation.distance(from: previousLocation)

        return elapsed >= 15 || distance >= 25
    }

    private func send(snapshot: DeviceLocationSnapshot) async {
        guard !isSendingUpdate else { return }
        guard let client else {
            latestErrorMessage = "Location sync is unavailable because the mobile session is missing."
            return
        }

        isSendingUpdate = true
        defer { isSendingUpdate = false }

        let formatter = ISO8601DateFormatter()

        do {
            let response: MobileLocationUpdateResponseDTO = try await client.post(
                MobileAPI.location,
                body: MobileLocationUpdateRequestBody(
                    latitude: snapshot.latitude,
                    longitude: snapshot.longitude,
                    accuracyMeters: snapshot.accuracyMeters,
                    headingDegrees: snapshot.headingDegrees,
                    speedMps: snapshot.speedMps,
                    capturedAt: formatter.string(from: snapshot.capturedAt)
                )
            )

            guard response.ok else { return }
            lastSentSnapshot = snapshot
            lastSentAt = formatter.date(from: response.capturedAt) ?? snapshot.capturedAt
            latestErrorMessage = nil
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }
}
