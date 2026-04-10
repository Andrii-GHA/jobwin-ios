import SwiftUI

enum JobWinPalette {
    static let primary = Color(red: 0.31, green: 0.35, blue: 0.95)
    static let accent = Color(red: 0.11, green: 0.70, blue: 0.61)
    static let canvas = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let surface = Color.white
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.18)
    static let muted = Color(red: 0.42, green: 0.47, blue: 0.58)
    static let border = Color(red: 0.87, green: 0.89, blue: 0.94)
}

struct JobWinCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(JobWinPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(JobWinPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
    }
}

extension View {
    func jobWinCard() -> some View {
        modifier(JobWinCardModifier())
    }
}
