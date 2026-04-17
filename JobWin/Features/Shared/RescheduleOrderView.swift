import SwiftUI

struct RescheduleOrderView: View {
    let title: String
    let initialStart: Date
    let initialEnd: Date
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: (Date, Date) -> Void

    @State private var startsAt: Date
    @State private var endsAt: Date

    init(
        title: String,
        initialStart: Date,
        initialEnd: Date,
        isSaving: Bool,
        errorMessage: String?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Date, Date) -> Void
    ) {
        self.title = title
        self.initialStart = initialStart
        self.initialEnd = initialEnd
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onSave = onSave
        _startsAt = State(initialValue: initialStart)
        _endsAt = State(initialValue: max(initialEnd, initialStart.addingTimeInterval(60 * 60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    DatePicker("Start", selection: $startsAt)
                    DatePicker("End", selection: $endsAt, in: startsAt...)
                }

                Section {
            Text("The job will be updated and the customer notification flow will use the new schedule.")
                        .font(.footnote)
                        .foregroundStyle(JobWinPalette.muted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        onSave(startsAt, endsAt)
                    }
                    .disabled(isSaving || endsAt < startsAt)
                }
            }
        }
    }
}
