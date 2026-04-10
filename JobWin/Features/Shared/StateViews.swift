import SwiftUI

struct LoadingStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.footnote)
                .foregroundStyle(JobWinPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(JobWinPalette.ink)

            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(JobWinPalette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(JobWinPalette.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jobWinCard()
    }
}

struct DetailLine: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JobWinPalette.ink)

            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CallSummaryCard: View {
    let summary: CallSummaryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(JobWinFormatting.displayStatus(summary.kind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JobWinPalette.ink)

                    if let metadata = JobWinFormatting.bulletJoin(
                        JobWinFormatting.displayStatus(summary.status),
                        JobWinFormatting.displayDateTime(summary.startedAt),
                        summary.durationSeconds.map { "\($0)s" }
                    ) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(JobWinPalette.muted)
                    }
                }

                Spacer()

                if let transferStatus = JobWinFormatting.normalizedText(summary.transferStatus) {
                    StatusBadge(text: JobWinFormatting.displayStatus(transferStatus), color: JobWinPalette.accent)
                }
            }

            if let summaryText = JobWinFormatting.normalizedText(summary.summary) {
                Text(summaryText)
                    .font(.body)
                    .foregroundStyle(JobWinPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let transcriptPreview = JobWinFormatting.normalizedText(summary.transcriptPreview), transcriptPreview != summary.summary {
                Text(transcriptPreview)
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(JobWinPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(JobWinPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

