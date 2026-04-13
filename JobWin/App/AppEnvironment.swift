import Foundation
import Observation

@Observable
final class AppEnvironment {
    var defaultBaseURL = "https://app.jobwin.io"
    let keychain = KeychainStore(service: "io.jobwin.mobile")
    let pushService = PushService()
    let activityStore = ActivityStore()
    let shellMetricsStore = ShellMetricsStore()
    let locationService = LocationService()
}
