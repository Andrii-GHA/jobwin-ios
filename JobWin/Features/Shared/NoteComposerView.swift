import SwiftUI

struct NoteComposerView: View {
    let title: String
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var noteBody = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Internal note")
                    .font(.headline)
                    .foregroundStyle(JobWinPalette.ink)

                TextEditor(text: $noteBody)
                    .frame(minHeight: 220)
                    .padding(12)
                    .background(JobWinPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(JobWinPalette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        onSave(noteBody)
                    }
                    .disabled(isSaving || noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
