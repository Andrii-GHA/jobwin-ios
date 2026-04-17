import Foundation
import Observation

struct AppRouteAccess: Equatable {
    let inbox: Bool
    let clients: Bool

    init(fullAccess: Bool) {
        inbox = fullAccess
        clients = fullAccess
    }
}

enum AppTab: Hashable {
    case home
    case calendar
    case orders
    case inbox
    case clients

    var title: String {
        switch self {
        case .home: return "Home"
        case .calendar: return "Calendar"
        case .orders: return "Jobs"
        case .inbox: return "Inbox"
        case .clients: return "Clients"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .calendar: return "calendar"
        case .orders: return "clipboard.text"
        case .inbox: return "bubble.left.and.bubble.right"
        case .clients: return "person.2"
        }
    }
}

enum OrdersRoute: Hashable {
    case detail(String)
}

enum HomeRoute: Hashable {
    case tasks
    case task(String)
}

enum ClientsRoute: Hashable {
    case detail(String)
}

enum InboxRoute: Hashable {
    case detail(String)
}

enum AppRoute: Equatable {
    case home
    case calendar
    case orders
    case tasks
    case inbox
    case clients
    case order(String)
    case task(String)
    case client(String)
    case thread(String)
    case webPath(String)

    init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" }

        guard scheme == "jobwin" else { return nil }

        switch host {
        case "home":
            self = .home
        case "calendar":
            self = .calendar
        case "jobs", "orders":
            self = .orders
        case "tasks":
            self = .tasks
        case "settings":
            self = .webPath("/settings")
        case "billing":
            self = .webPath("/billing")
        case "logs":
            self = .webPath(url.path.isEmpty ? "/logs" : "/logs\(url.query.map { "?\($0)" } ?? "")")
        case "estimate":
            self = .webPath(pathParts.first.map { "/estimates/\($0)" } ?? "/estimates")
        case "invoice":
            self = .webPath(pathParts.first.map { "/invoices/\($0)" } ?? "/invoices")
        case "estimates":
            self = .webPath(pathParts.first.map { "/estimates/\($0)" } ?? "/estimates")
        case "invoices":
            self = .webPath(pathParts.first.map { "/invoices/\($0)" } ?? "/invoices")
        case "inbox":
            self = .inbox
        case "clients":
            self = .clients
        case "job", "order":
            guard let id = pathParts.first, !id.isEmpty else { return nil }
            self = .order(id)
        case "task":
            guard let id = pathParts.first, !id.isEmpty else { return nil }
            self = .task(id)
        case "client":
            guard let id = pathParts.first, !id.isEmpty else { return nil }
            self = .client(id)
        case "thread":
            guard let id = pathParts.first, !id.isEmpty else { return nil }
            self = .thread(id)
        default:
            return nil
        }
    }

    init?(href: String) {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        let parts = path.split(separator: "/").map(String.init)

        guard let first = parts.first?.lowercased() else {
            self = .home
            return
        }

        switch first {
        case "dashboard", "home":
            self = .home
        case "calendar":
            self = .calendar
        case "jobs", "orders":
            if parts.count > 1 {
                self = .order(parts[1])
            } else {
                self = .orders
            }
        case "job":
            if parts.count > 1 {
                self = .order(parts[1])
            } else {
                self = .orders
            }
        case "tasks":
            if parts.count > 1 {
                self = .task(parts[1])
            } else {
                self = .tasks
            }
        case "settings":
            self = .webPath("/settings")
        case "billing":
            self = .webPath("/billing")
        case "logs":
            self = .webPath(path)
        case "estimate":
            self = .webPath(parts.count > 1 ? "/estimates/\(parts[1])" : "/estimates")
        case "invoice":
            self = .webPath(parts.count > 1 ? "/invoices/\(parts[1])" : "/invoices")
        case "estimates":
            self = .webPath(parts.count > 1 ? "/estimates/\(parts[1])" : "/estimates")
        case "invoices":
            self = .webPath(parts.count > 1 ? "/invoices/\(parts[1])" : "/invoices")
        case "clients", "leads":
            if parts.count > 1 {
                self = .client(parts[1])
            } else {
                self = .clients
            }
        case "inbox":
            if parts.count > 2, parts[1].lowercased() == "threads" {
                self = .thread(parts[2])
            } else {
                self = .inbox
            }
        default:
            return nil
        }
    }

    init?(pushUserInfo: [AnyHashable: Any]) {
        let jobwin: [AnyHashable: Any]
        if let value = pushUserInfo["jobwin"] as? [AnyHashable: Any] {
            jobwin = value
        } else if let value = pushUserInfo["jobwin"] as? [String: Any] {
            jobwin = value.reduce(into: [AnyHashable: Any]()) { partialResult, item in
                partialResult[item.key] = item.value
            }
        } else {
            return nil
        }

        if let href = jobwin["href"] as? String, let route = AppRoute(href: href) {
            self = route
            return
        }

        let entityType = (jobwin["entityType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let entityId = (jobwin["entityId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !entityType.isEmpty else { return nil }

        switch entityType {
        case "appointment", "job", "jobs", "order", "booking", "bookings":
            self = entityId.isEmpty ? .orders : .order(entityId)
        case "task":
            self = entityId.isEmpty ? .tasks : .task(entityId)
        case "estimate":
            self = .webPath(entityId.isEmpty ? "/estimates" : "/estimates/\(entityId)")
        case "invoice":
            self = .webPath(entityId.isEmpty ? "/invoices" : "/invoices/\(entityId)")
        case "payment", "payments":
            self = .webPath("/billing")
        case "ai_call", "ai_calls", "phone_interaction":
            self = .inbox
        case "lead", "client", "customer":
            self = entityId.isEmpty ? .clients : .client(entityId)
        case "communication", "message", "thread":
            self = entityId.isEmpty ? .inbox : .thread(entityId)
        default:
            return nil
        }
    }

    func isAccessible(access: AppRouteAccess) -> Bool {
        switch self {
        case .clients, .client:
            return access.clients
        case .inbox, .thread:
            return access.inbox
        default:
            return true
        }
    }
}

struct ExternalWebDestination: Identifiable, Equatable {
    let path: String

    var id: String { path }
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [HomeRoute] = []
    var ordersPath: [OrdersRoute] = []
    var clientsPath: [ClientsRoute] = []
    var inboxPath: [InboxRoute] = []
    var presentedWebDestination: ExternalWebDestination?

    private var pendingRoute: AppRoute?

    func handle(url: URL, access: AppRouteAccess, isAuthenticated: Bool) {
        guard let route = AppRoute(url: url) else { return }
        open(route: route, access: access, isAuthenticated: isAuthenticated)
    }

    func open(route: AppRoute, access: AppRouteAccess, isAuthenticated: Bool) {
        guard isAuthenticated else {
            pendingRoute = route
            return
        }

        pendingRoute = nil
        apply(route: route, access: access)
    }

    func consumePendingRouteIfPossible(access: AppRouteAccess, isAuthenticated: Bool) {
        guard isAuthenticated, let pendingRoute else { return }
        self.pendingRoute = nil
        apply(route: pendingRoute, access: access)
    }

    func resetForSignOut() {
        pendingRoute = nil
        selectedTab = .home
        clearPaths()
    }

    private func apply(route: AppRoute, access: AppRouteAccess) {
        switch route {
        case .home:
            clearPaths()
            selectedTab = .home

        case .calendar:
            clearPaths()
            selectedTab = .calendar

        case .tasks:
            clearPaths()
            selectedTab = .home
            homePath = [.tasks]

        case .orders:
            clearPaths()
            selectedTab = .orders

        case let .task(id):
            clearPaths()
            selectedTab = .home
            homePath = [.task(id)]

        case let .order(id):
            clearPaths()
            selectedTab = .orders
            ordersPath = [.detail(id)]

        case .clients:
            guard access.clients else {
                clearPaths()
                selectedTab = .home
                return
            }
            clearPaths()
            selectedTab = .clients

        case let .client(id):
            guard access.clients else {
                clearPaths()
                selectedTab = .home
                return
            }
            clearPaths()
            selectedTab = .clients
            clientsPath = [.detail(id)]

        case .inbox:
            guard access.inbox else {
                clearPaths()
                selectedTab = .home
                return
            }
            clearPaths()
            selectedTab = .inbox

        case let .thread(id):
            guard access.inbox else {
                clearPaths()
                selectedTab = .home
                return
            }
            clearPaths()
            selectedTab = .inbox
            inboxPath = [.detail(id)]

        case let .webPath(path):
            clearPaths()
            selectedTab = .home
            presentedWebDestination = ExternalWebDestination(path: path)
        }
    }

    private func clearPaths() {
        homePath = []
        ordersPath = []
        clientsPath = []
        inboxPath = []
        presentedWebDestination = nil
    }
}
