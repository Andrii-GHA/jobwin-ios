import Foundation
import UIKit

enum MessageRouting {
    static func openText(to phoneNumber: String) {
        guard let normalized = normalizedPhone(phoneNumber) else { return }

        let candidates = [
            "sms:\(normalized)",
            "sms://\(normalized)",
        ]

        for value in candidates {
            guard let url = URL(string: value), UIApplication.shared.canOpenURL(url) else { continue }
            UIApplication.shared.open(url)
            return
        }
    }

    private static func normalizedPhone(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let filtered = trimmed.filter { $0.isNumber || $0 == "+" }
        return filtered.isEmpty ? nil : filtered
    }
}
