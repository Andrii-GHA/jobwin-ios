import Foundation

enum JobWinFormatting {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func displayDateTime(_ value: String?) -> String? {
        guard let date = parseDate(value) else { return normalizedText(value) }
        return dateTimeFormatter.string(from: date)
    }

    static func displayDate(_ value: String?) -> String? {
        guard let date = parseDate(value) else { return normalizedText(value) }
        return dateFormatter.string(from: date)
    }

    static func displayTime(_ value: String?) -> String? {
        guard let date = parseDate(value) else { return normalizedText(value) }
        return timeFormatter.string(from: date)
    }

    static func displayStatus(_ value: String?) -> String {
        normalizedText(value)?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized ?? "Unknown"
    }

    static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func bulletJoin(_ values: String?...) -> String? {
        let parts = values.compactMap { normalizedText($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    static func date(from value: String?) -> Date? {
        parseDate(value)
    }

    static func iso8601String(from date: Date) -> String {
        isoWithFractional.string(from: date)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let normalized = normalizedText(value) else { return nil }
        if let date = isoWithFractional.date(from: normalized) {
            return date
        }
        if let date = isoStandard.date(from: normalized) {
            return date
        }
        return nil
    }
}
