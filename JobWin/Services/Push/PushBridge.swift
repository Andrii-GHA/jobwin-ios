import Foundation

final class PushBridge {
    static let shared = PushBridge()

    var onDeviceToken: ((Data) -> Void)?
    var onNotificationUserInfo: (([AnyHashable: Any]) -> Void)?
    var onForegroundNotificationUserInfo: (([AnyHashable: Any]) -> Void)?
    var onRegistrationError: ((String) -> Void)?

    private init() {}
}
