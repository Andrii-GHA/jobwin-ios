import CoreLocation
import MapKit
import SwiftUI

@Observable
final class LiveMapModel {
    private let client: APIClient

    var isLoading = false
    var errorMessage: String?
    var technicians: [MobileTechnicianLocationDTO] = []

    init(client: APIClient) {
        self.client = client
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let payload: MobileTechnicianLocationsDTO = try await client.get(MobileAPI.locationTechnicians)
            technicians = payload.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LiveMapView: View {
    let sessionStore: SessionStore
    let orders: [OrderSummaryDTO]

    @State private var model: LiveMapModel?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingStateView(title: "Preparing live map...")
            }
        }
        .task {
            guard let client = sessionStore.makeAPIClient() else { return }
            if model == nil {
                model = LiveMapModel(client: client)
            }
            await model?.refresh()
            recenterMap()
        }
    }

    @ViewBuilder
    private func content(model: LiveMapModel) -> some View {
        let locationService = sessionStore.environment.locationService
        let hasVisiblePins = !model.technicians.isEmpty || locationService.lastSnapshot != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sharingCard(locationService: locationService, model: model)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if hasVisiblePins {
                    Map(position: $cameraPosition) {
                        ForEach(model.technicians) { technician in
                            Annotation(technician.label, coordinate: CLLocationCoordinate2D(
                                latitude: technician.latitude,
                                longitude: technician.longitude
                            )) {
                                TechnicianPinView(
                                    title: technician.isCurrentUser ? "You" : technician.label,
                                    subtitle: freshnessLabel(technician.freshness),
                                    color: Color(hex: technician.color) ?? JobWinPalette.primary,
                                    emphasized: technician.isCurrentUser
                                )
                            }
                        }

                        if let snapshot = locationService.lastSnapshot,
                           !model.technicians.contains(where: { $0.isCurrentUser })
                        {
                            Annotation("You", coordinate: snapshot.coordinate) {
                                TechnicianPinView(
                                    title: "You",
                                    subtitle: "Device",
                                    color: JobWinPalette.primary,
                                    emphasized: true
                                )
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .frame(minHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(JobWinPalette.border, lineWidth: 1)
                    )
                } else {
                    ContentUnavailableView(
                        "No live map points yet",
                        systemImage: "location.slash",
                        description: Text("Turn on location sharing on the technician device and keep the app open while on duty.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .jobWinCard()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Live technicians")
                        .font(.headline)
                    Text("\(model.technicians.count) technicians visible | \(orders.count) scheduled jobs")
                        .font(.subheadline)
                        .foregroundStyle(JobWinPalette.muted)
                }
                .jobWinCard()

                if !model.technicians.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Technician status")
                            .font(.headline)

                        ForEach(model.technicians) { technician in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(technician.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    JobWinFormatting.bulletJoin(
                                        freshnessLabel(technician.freshness),
                                        technician.accuracyMeters.map { "~\(Int($0))m" },
                                        JobWinFormatting.displayDateTime(technician.capturedAt)
                                    ) ?? "No location metadata"
                                )
                                .font(.footnote)
                                .foregroundStyle(JobWinPalette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .jobWinCard()
                }
            }
            .padding(16)
        }
        .refreshable {
            await model.refresh()
            recenterMap()
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                recenterMap()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    @ViewBuilder
    private func sharingCard(locationService: LocationService, model: LiveMapModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location sharing")
                .font(.headline)

            Text(sharingStateLabel(locationService.sharingState))
                .font(.subheadline)
                .foregroundStyle(JobWinPalette.ink)

            if let lastSentAt = locationService.lastSentAt {
                Text("Last sent: \(JobWinFormatting.displayDateTime(JobWinFormatting.iso8601String(from: lastSentAt)) ?? JobWinFormatting.iso8601String(from: lastSentAt))")
                    .font(.footnote)
                    .foregroundStyle(JobWinPalette.muted)
            }

            if let latestErrorMessage = locationService.latestErrorMessage {
                Text(latestErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(locationService.wantsSharing ? "Stop sharing" : "Share my location") {
                    Task {
                        if locationService.wantsSharing {
                            await locationService.stopSharing()
                        } else {
                            await locationService.startSharing(using: sessionStore)
                        }
                        await model.refresh()
                        recenterMap()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh map") {
                    Task {
                        await model.refresh()
                        recenterMap()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .jobWinCard()
    }

    private func recenterMap() {
        let technicians = model?.technicians ?? []
        let fallback = sessionStore.environment.locationService.lastSnapshot
        let coordinates = technicians.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } + (fallback.map { [$0.coordinate] } ?? [])

        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.04, (maxLatitude - minLatitude) * 1.6),
            longitudeDelta: max(0.04, (maxLongitude - minLongitude) * 1.6)
        )

        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func freshnessLabel(_ freshness: MobileLocationFreshness) -> String {
        switch freshness {
        case .live:
            return "Live"
        case .recent:
            return "Recent"
        case .stale:
            return "Stale"
        }
    }

    private func sharingStateLabel(_ state: LocationSharingState) -> String {
        switch state {
        case .idle:
            return "Location sharing is off."
        case .requestingPermission:
            return "Waiting for location permission."
        case .active:
            return "Live location sharing is active."
        case .paused:
            return "Sharing will resume when the app returns to the foreground."
        case .blocked:
            return "Location access is blocked."
        }
    }
}

private struct TechnicianPinView: View {
    let title: String
    let subtitle: String
    let color: Color
    let emphasized: Bool

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: emphasized ? 22 : 18, height: emphasized ? 22 : 18)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)

            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JobWinPalette.ink)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(JobWinPalette.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
