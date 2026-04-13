import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushService {
    private let deviceIdKey = "jobwin.push.deviceId"
    private let appEnvironmentNameKey = "jobwin.push.environment"

    var deviceId: String
    var deviceToken: String?
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var latestErrorMessage: String?
    var latestRegisteredTokenId: String?
    var pendingRoute: AppRoute?
    var foregroundRefreshToken = 0

    init() {
        let storedDeviceId = UserDefaults.standard.string(forKey: deviceIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedDeviceId, !storedDeviceId.isEmpty {
            deviceId = storedDeviceId
        } else {
            let generated = UUID().uuidString.lowercased()
            deviceId = generated
            UserDefaults.standard.set(generated, forKey: deviceIdKey)
        }

        PushBridge.shared.onDeviceToken = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleDeviceToken(data)
            }
        }

        PushBridge.shared.onNotificationUserInfo = { [weak self] userInfo in
            Task { @MainActor [weak self] in
                self?.handleNotification(userInfo: userInfo)
            }
        }

        PushBridge.shared.onForegroundNotificationUserInfo = { [weak self] userInfo in
            Task { @MainActor [weak self] in
                self?.handleForegroundNotification(userInfo: userInfo)
            }
        }

        PushBridge.shared.onRegistrationError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.latestErrorMessage = message
            }
        }
    }

    func configure(using sessionStore: SessionStore) async {
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }

        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
        await syncRegistrationIfPossible(using: sessionStore)
    }

    func reloadAuthorizationStatus() async {
        await refreshAuthorizationStatus()
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }

    func clearSessionState() {
        latestRegisteredTokenId = nil
        latestErrorMessage = nil
        pendingRoute = nil
    }

    func unregisterIfPossible(using sessionStore: SessionStore) async {
        guard let client = sessionStore.makeAPIClient() else { return }

        do {
            let response: PushUnregisterResponseDTO = try await client.delete(MobileAPI.pushRegister(deviceId: deviceId))
            guard response.ok else { return }
            latestRegisteredTokenId = nil
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    func syncRegistrationIfPossible(using sessionStore: SessionStore) async {
        guard let token = deviceToken, !token.isEmpty else { return }
        guard let client = sessionStore.makeAPIClient() else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }

        do {
            let response: PushRegisterResponseDTO = try await client.post(
                MobileAPI.pushRegisterRoot,
                body: PushRegisterRequestBody(
                    deviceId: deviceId,
                    deviceToken: token,
                    platform: "ios",
                    environment: currentEnvironment,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                    locale: Locale.current.identifier,
                    timeZone: TimeZone.current.identifier
                )
            )
            guard response.ok else { return }
            latestRegisteredTokenId = response.token.id
            latestErrorMessage = nil
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            latestErrorMessage = error.localizedDescription
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func handleDeviceToken(_ data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
    }

    private func handleNotification(userInfo: [AnyHashable: Any]) {
        pendingRoute = AppRoute(pushUserInfo: userInfo)
    }

    private func handleForegroundNotification(userInfo: [AnyHashable: Any]) {
        guard AppRoute(pushUserInfo: userInfo) != nil else { return }
        foregroundRefreshToken += 1
    }

    private var currentEnvironment: String {
        if let stored = UserDefaults.standard.string(forKey: appEnvironmentNameKey)?.lowercased(),
           ["development", "staging", "production"].contains(stored) {
            return stored
        }

        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}
