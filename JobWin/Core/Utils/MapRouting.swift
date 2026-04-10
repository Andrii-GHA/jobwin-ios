import Foundation
import UIKit

enum MapRouting {
    static func openDirections(to address: String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let candidates = [
            "maps://?daddr=\(encoded)&dirflg=d",
            "http://maps.apple.com/?daddr=\(encoded)&dirflg=d",
        ]

        for value in candidates {
            guard let url = URL(string: value), UIApplication.shared.canOpenURL(url) else { continue }
            UIApplication.shared.open(url)
            return
        }
    }
}
