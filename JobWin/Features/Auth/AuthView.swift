import SwiftUI

struct AuthView: View {
    let sessionStore: SessionStore

    @State private var apiBaseURL = "https://app.jobwin.io"
    @State private var accessToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("JobWin")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(JobWinPalette.ink)
                Text("Connect the native client to the JobWin mobile API using a Supabase access token.")
                    .font(.body)
                    .foregroundStyle(JobWinPalette.muted)
            }

            VStack(spacing: 14) {
                TextField("API base URL", text: $apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(JobWinPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(JobWinPalette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                SecureField("Supabase access token", text: $accessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(JobWinPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(JobWinPalette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                Task {
                    await sessionStore.signIn(baseURL: apiBaseURL, accessToken: accessToken)
                }
            } label: {
                HStack {
                    Spacer()
                    if case .authenticating = sessionStore.status {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Connect")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(JobWinPalette.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if case let .failed(message) = sessionStore.status {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
        .background(JobWinPalette.canvas.ignoresSafeArea())
    }
}
