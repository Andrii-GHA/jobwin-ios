import Foundation

enum MobileAPI {
    static let session = "/api/mobile/v1/session"
    static let bootstrap = "/api/mobile/v1/bootstrap"
    static let activityRoot = "/api/mobile/v1/activity"
    static let home = "/api/mobile/v1/home"
    static let calendar = "/api/mobile/v1/calendar"
    static let orders = "/api/mobile/v1/orders"
    static let clients = "/api/mobile/v1/clients"
    static let tasks = "/api/mobile/v1/tasks"
    static let inboxThreads = "/api/mobile/v1/inbox/threads"
    static let ringOut = "/api/mobile/v1/calls/ring-out"
    static let pushRegisterRoot = "/api/mobile/v1/push/register"

    static func order(_ orderId: String) -> String {
        "\(orders)/\(orderId)"
    }

    static func orderField(_ orderId: String, action: String) -> String {
        "\(order(orderId))/\(action)"
    }

    static func orderReschedule(_ orderId: String) -> String {
        "\(order(orderId))/reschedule"
    }

    static func client(_ clientId: String) -> String {
        "\(clients)/\(clientId)"
    }

    static func clientNote(_ clientId: String) -> String {
        "\(client(clientId))/note"
    }

    static func task(_ taskId: String) -> String {
        "\(tasks)/\(taskId)"
    }

    static func taskComplete(_ taskId: String) -> String {
        "\(task(taskId))/complete"
    }

    static func tasksList(scope: String, status: String = "open", limit: Int = 100) -> String {
        "\(tasks)?scope=\(scope)&status=\(status)&limit=\(limit)"
    }

    static func inboxThread(_ threadId: String) -> String {
        "\(inboxThreads)/\(threadId)"
    }

    static func inboxThreadNote(_ threadId: String) -> String {
        "\(inboxThread(threadId))/note"
    }

    static func pushRegister(deviceId: String) -> String {
        "\(pushRegisterRoot)/\(deviceId)"
    }

    static func activityFeed(limit: Int) -> String {
        "\(activityRoot)?limit=\(max(1, min(limit, 100)))"
    }
}
