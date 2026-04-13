import Foundation
import CoreLocation

struct DeviceLocationSnapshot: Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let headingDegrees: Double?
    let speedMps: Double?
    let capturedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum LocationSharingState: Equatable {
    case idle
    case requestingPermission
    case active
    case paused
    case blocked
}
