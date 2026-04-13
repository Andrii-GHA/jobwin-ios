import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    enum Status: Equatable {
        case idle
        case restoring
        case authenticating
        case authenticated
        case failed(String)
    }

    struct SessionIdentity: Codable, Equatable {
        let userId: String
        let email: String?
        let workspaceId: String
        let rawRole: String
        let mobileRole: String
        let fullAccess: Bool
    }

    let environment: AppEnvironment

    var apiBaseURL: String
    var accessToken: String = ""
    var status: Status = .idle
    var identity: SessionIdentity?

    var isAuthenticated: Bool {
        identity != nil
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.apiBaseURL = environment.defaultBaseURL
    }

    func restoreIfPossible() async {
        guard case .idle = status else { return }

        status = .restoring

        let savedBaseURL = UserDefaults.standard.string(forKey: "jobwin.apiBaseURL")
        let savedToken = environment.keychain.read(key: "jobwin.accessToken") ?? ""

        if let savedBaseURL, !savedBaseURL.isEmpty {
            apiBaseURL = savedBaseURL
        }

        accessToken = savedToken

        guard !accessToken.isEmpty else {
            status = .idle
            return
        }

        await refreshSession()
    }

    func signIn(baseURL: String, accessToken: String) async {
        apiBaseURL = normalizeBaseURL(baseURL)
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        status = .authenticating
        await refreshSession()
    }

    func signOut() {
        environment.locationService.resetAfterSignOut()
        identity = nil
        accessToken = ""
        status = .idle
        environment.pushService.clearSessionState()
        environment.keychain.delete(key: "jobwin.accessToken")
    }

    func makeAPIClient() -> APIClient? {
        guard !accessToken.isEmpty else {
            return nil
        }

        return APIClient(baseURL: apiBaseURL, accessToken: accessToken)
    }

    private func refreshSession() async {
        guard let client = makeAPIClient() else {
            status = .failed("Missing access token.")
            return
        }

        do {
            let response: MobileAuthSessionDTO = try await client.post(MobileAPI.session, body: EmptyBody())
            identity = SessionIdentity(
                userId: response.user.id,
                email: response.user.email,
                workspaceId: response.workspaceId,
                rawRole: response.rawRole,
                mobileRole: response.mobileRole,
                fullAccess: response.fullAccess
            )
            environment.keychain.write(value: accessToken, key: "jobwin.accessToken")
            UserDefaults.standard.set(apiBaseURL, forKey: "jobwin.apiBaseURL")
            status = .authenticated
        } catch let error as APIClientError {
            identity = nil

            if case let .requestFailed(statusCode, _) = error, statusCode == 401 || statusCode == 403 {
                accessToken = ""
                environment.keychain.delete(key: "jobwin.accessToken")
                environment.pushService.clearSessionState()
            }

            status = .failed(error.localizedDescription)
        } catch {
            identity = nil
            status = .failed(error.localizedDescription)
        }
    }

    private func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return environment.defaultBaseURL
        }

        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}
