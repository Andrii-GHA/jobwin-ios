import Foundation

struct EmptyBody: Encodable {}

struct MobileUserDTO: Codable, Identifiable, Hashable {
    let id: String
    let email: String?
    let displayName: String?
}

struct MobileAuthSessionDTO: Codable {
    let authenticated: Bool
    let user: MobileUserDTO
    let workspaceId: String
    let rawRole: String
    let mobileRole: String
    let fullAccess: Bool
}

struct MobileBootstrapDTO: Codable {
    struct WorkspaceDTO: Codable {
        let id: String
        let name: String?
        let businessName: String?
    }

    struct MembershipDTO: Codable {
        let rawRole: String
        let mobileRole: String
        let fullAccess: Bool
    }

    struct CapabilitiesDTO: Codable {
        let home: Bool
        let calendar: Bool
        let inbox: Bool
        let orders: Bool
        let clients: Bool
        let tasks: Bool
        let ringOut: Bool
    }

    struct AIPhoneDTO: Codable {
        let active: Bool
        let phoneNumber: String?
    }

    let user: MobileUserDTO
    let workspace: WorkspaceDTO
    let membership: MembershipDTO
    let capabilities: CapabilitiesDTO
    let aiPhone: AIPhoneDTO
}

struct NotificationPreferencesDTO: Codable {
    var orders: Bool
    var clients: Bool
    var bookings: Bool
    var payments: Bool
    var aiCalls: Bool
    var estimates: Bool
    var system: Bool
    var popupAlerts: Bool
}

struct ActivityItemDTO: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let href: String?
    let category: String
    let icon: String
    let createdAt: String
    let createdAtLabel: String
    let unread: Bool
}

struct ActivitySnapshotDTO: Codable {
    let items: [ActivityItemDTO]
    let unreadCount: Int
    let preferences: NotificationPreferencesDTO
}

struct MarkAllActivityReadBody: Encodable {
    let action: String
}

struct ActivityPreferencesPatchBody: Encodable {
    let preferences: NotificationPreferencesDTO
}

struct OrderSummaryDTO: Codable, Identifiable, Hashable {
    let id: String
    let clientId: String?
    let clientPhone: String?
    let orderNumber: String
    let title: String
    let clientName: String
    let startsAt: String?
    let endsAt: String?
    let status: String
    let technicianName: String?
    let address: String?
}

struct ClientSummaryDTO: Codable, Identifiable, Hashable {
    let id: String
    let threadId: String?
    let latestOrderId: String?
    let displayName: String
    let primaryPhone: String?
    let primaryEmail: String?
    let address: String?
    let source: String?
    let status: String
    let lastActivityAt: String?
    let nextBestAction: String?
    let unreadCount: Int
}

struct TaskSummaryDTO: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueAt: String?
    let relatedClientId: String?
    let relatedOrderId: String?
}

struct InboxThreadSummaryDTO: Codable, Identifiable, Hashable {
    let id: String
    let clientId: String?
    let clientPhone: String?
    let clientAddress: String?
    let title: String
    let lastPreview: String
    let lastAt: String
    let unread: Bool
    let hasAiCalls: Bool
    let hasHumanCalls: Bool
    let hasTransfer: Bool
    let needsFollowUp: Bool
}

struct HomeOperationsDTO: Codable {
    let todayOrders: [OrderSummaryDTO]
    let missedCalls: [InboxThreadSummaryDTO]
    let followUpQueue: [ClientSummaryDTO]
    let urgentTasks: [TaskSummaryDTO]
    let unreadInboxCount: Int
    let tasksAvailable: Bool
}

struct MobileOrdersListDTO: Codable {
    let items: [OrderSummaryDTO]
}

struct MobileClientsListDTO: Codable {
    let items: [ClientSummaryDTO]
}

struct MobileTasksListDTO: Codable {
    let items: [TaskSummaryDTO]
    let tasksAvailable: Bool
}

struct TaskDetailDTO: Codable {
    struct TaskDTO: Codable, Identifiable, Hashable {
        let id: String
        let title: String
        let status: String
        let priority: String
        let dueAt: String?
        let relatedClientId: String?
        let relatedOrderId: String?
        let leadId: String?
        let details: String?
        let completedAt: String?
    }

    let task: TaskDTO
    let client: ClientSummaryDTO?
    let recentThread: InboxThreadSummaryDTO?
    let relatedOrders: [OrderSummaryDTO]
}

struct MobileInboxThreadsDTO: Codable {
    let items: [InboxThreadSummaryDTO]
}

struct MobileCalendarDTO: Codable {
    let from: String?
    let to: String?
    let orders: [OrderSummaryDTO]
    let tasks: [TaskSummaryDTO]
    let tasksAvailable: Bool
}

enum MobileLocationFreshness: String, Codable {
    case live
    case recent
    case stale
}

struct MobileLocationUpdateRequestBody: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let headingDegrees: Double?
    let speedMps: Double?
    let capturedAt: String?
}

struct MobileLocationUpdateResponseDTO: Codable {
    let ok: Bool
    let capturedAt: String
    let sharingEnabled: Bool
}

struct MobileLocationStopResponseDTO: Codable {
    let ok: Bool
    let sharingEnabled: Bool
}

struct MobileTechnicianLocationDTO: Codable, Identifiable, Hashable {
    var id: String { userId }

    let userId: String
    let label: String
    let color: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let headingDegrees: Double?
    let speedMps: Double?
    let capturedAt: String
    let freshness: MobileLocationFreshness
    let isCurrentUser: Bool
}

struct MobileTechnicianLocationsDTO: Codable {
    let items: [MobileTechnicianLocationDTO]
}

struct TaskMutationTaskDTO: Codable {
    let id: String
    let leadId: String?
    let status: String
    let completedAt: String?
}

struct TaskMutationResponseDTO: Codable {
    let ok: Bool
    let task: TaskMutationTaskDTO
}

struct NoteMutationNoteDTO: Codable {
    let id: String
    let leadId: String
    let body: String
    let createdAt: String
}

struct NoteMutationResponseDTO: Codable {
    let ok: Bool
    let note: NoteMutationNoteDTO
}

struct NoteRequestBody: Encodable {
    let body: String
}

struct AppointmentFieldStateDTO: Codable {
    let arrivedAt: String?
    let startedAt: String?
    let completedAt: String?
}

struct OrderFieldEventResponseDTO: Codable {
    let ok: Bool
    let fieldState: AppointmentFieldStateDTO
}

struct RingOutResponseDTO: Codable {
    let ok: Bool
    let callSid: String?
    let workspacePhoneNumberId: String?
    let customerId: String?
    let customerPhone: String?
}

struct RingOutRequestBody: Encodable {
    let leadId: String?
    let clientId: String?
}

struct RescheduleRequestBody: Encodable {
    let startsAt: String
    let endsAt: String
}

struct RescheduleResponseDTO: Codable {
    let ok: Bool
    let status: String
    let startsAt: String
    let endsAt: String
}

struct PushRegisterRequestBody: Encodable {
    let deviceId: String
    let deviceToken: String
    let platform: String
    let environment: String
    let appVersion: String?
    let appBuild: String?
    let locale: String?
    let timeZone: String?
}

struct PushRegisterTokenDTO: Codable {
    let id: String
    let deviceId: String
    let platform: String
    let environment: String
    let lastRegisteredAt: String
}

struct PushRegisterResponseDTO: Codable {
    let ok: Bool
    let token: PushRegisterTokenDTO
}

struct PushUnregisterResponseDTO: Codable {
    let ok: Bool
    let deviceId: String
    let disabledAt: String
}

enum OrderFieldAction: String, CaseIterable, Identifiable {
    case arrived
    case start
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrived: return "Arrived"
        case .start: return "Start"
        case .complete: return "Complete"
        }
    }

    var successMessage: String {
        switch self {
        case .arrived: return "Marked as arrived."
        case .start: return "Work started."
        case .complete: return "Order completed."
        }
    }
}

struct CallSummaryDTO: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let startedAt: String
    let durationSeconds: Int?
    let status: String
    let summary: String?
    let transcript: String?
    let transcriptPreview: String?
    let transcriptStatus: String?
    let summaryStatus: String?
    let recordingStatus: String?
    let recordingUrl: String?
    let transferStatus: String?
}

struct MessageTimelineItemDTO: Codable, Hashable {
    let id: String
    let kind: String
    let at: String
    let direction: String
    let channel: String?
    let messageType: String?
    let body: String
}

struct CallTimelineItemDTO: Codable, Hashable {
    let id: String
    let kind: String
    let at: String
    let call: CallSummaryDTO
}

enum TimelineItemDTO: Codable, Hashable, Identifiable {
    case message(MessageTimelineItemDTO)
    case call(CallTimelineItemDTO)

    var id: String {
        switch self {
        case let .message(item):
            return item.id
        case let .call(item):
            return item.id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case at
        case direction
        case channel
        case messageType
        case body
        case call
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        if kind == "message" {
            self = .message(
                MessageTimelineItemDTO(
                    id: try container.decode(String.self, forKey: .id),
                    kind: kind,
                    at: try container.decode(String.self, forKey: .at),
                    direction: try container.decode(String.self, forKey: .direction),
                    channel: try container.decodeIfPresent(String.self, forKey: .channel),
                    messageType: try container.decodeIfPresent(String.self, forKey: .messageType),
                    body: try container.decode(String.self, forKey: .body)
                )
            )
            return
        }

        self = .call(
            CallTimelineItemDTO(
                id: try container.decode(String.self, forKey: .id),
                kind: kind,
                at: try container.decode(String.self, forKey: .at),
                call: try container.decode(CallSummaryDTO.self, forKey: .call)
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(item):
            try container.encode(item.kind, forKey: .kind)
            try container.encode(item.id, forKey: .id)
            try container.encode(item.at, forKey: .at)
            try container.encode(item.direction, forKey: .direction)
            try container.encodeIfPresent(item.channel, forKey: .channel)
            try container.encodeIfPresent(item.messageType, forKey: .messageType)
            try container.encode(item.body, forKey: .body)
        case let .call(item):
            try container.encode(item.kind, forKey: .kind)
            try container.encode(item.id, forKey: .id)
            try container.encode(item.at, forKey: .at)
            try container.encode(item.call, forKey: .call)
        }
    }
}

struct ClientDetailClientDTO: Codable, Hashable {
    let id: String
    let displayName: String
    let primaryPhone: String?
    let primaryEmail: String?
    let source: String?
    let status: String
    let lastActivityAt: String?
    let nextBestAction: String?
    let unreadCount: Int
    let title: String?
    let address: String?
    let jobDescription: String?
}

struct ClientDetailDTO: Codable {
    let client: ClientDetailClientDTO
    let recentOrders: [OrderSummaryDTO]
    let recentTasks: [TaskSummaryDTO]
    let recentCallSummaries: [CallSummaryDTO]
    let recentThread: InboxThreadSummaryDTO?
}

struct InboxThreadDetailClientDTO: Codable, Hashable {
    let id: String
    let displayName: String
    let primaryPhone: String?
    let primaryEmail: String?
    let address: String?
    let status: String
    let source: String?
}

struct InboxThreadDetailDTO: Codable {
    let thread: InboxThreadSummaryDTO
    let client: InboxThreadDetailClientDTO
    let nextBestAction: String?
    let timeline: [TimelineItemDTO]
}

struct OrderDetailOrderDTO: Codable, Hashable {
    let id: String
    let orderNumber: String
    let title: String
    let clientName: String
    let startsAt: String?
    let endsAt: String?
    let status: String
    let technicianName: String?
    let address: String?
    let notes: String?
    let serviceDetails: [String: String]
    let importantMessage: Bool
    let warrantyCallback: Bool
}

struct OrderDetailDTO: Codable {
    let order: OrderDetailOrderDTO
    let client: ClientSummaryDTO?
    let callSummaries: [CallSummaryDTO]
    let tasks: [TaskSummaryDTO]
}

