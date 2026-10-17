import SwiftUI
import MapKit

struct LocationHistoryView: View {
    @Environment(GarageStore.self) private var store

    private var points: [HistoryPoint] {
        store.history.locationPoints(lastDays: 30)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LocationHistoryMap(points: points)

                if let latest = points.last {
                    LocationHistoryLatestPoint(point: latest)
                }

                Text("Konum geçmişi yalnızca uygulama açıkken alınan canlı telemetri kayıtlarından oluşur ve cihazda saklanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .glassCard()
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Konum geçmişi")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct LocationHistoryMap: View {
    let points: [HistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Son 30 gün")
                .font(.headline)

            if points.isEmpty {
                ContentUnavailableView(
                    "Henüz konum kaydı yok",
                    systemImage: "map",
                    description: Text("Canlı konum yenilendikçe harita oluşur.")
                )
                .frame(height: 260)
            } else {
                Map(initialPosition: .automatic) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        if let latitude = point.latitude, let longitude = point.longitude {
                            Marker(
                                index == points.count - 1 ? "Son park yeri" : "Kayıt \(index + 1)",
                                systemImage: index == points.count - 1 ? "car.fill" : "mappin",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: latitude,
                                    longitude: longitude
                                )
                            )
                            .tint(index == points.count - 1 ? Color.accentColor : .secondary)
                        }
                    }
                }
                .mapStyle(.standard)
                .frame(height: 320)
                .clipShape(.rect(cornerRadius: 18))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct LocationHistoryLatestPoint: View {
    let point: HistoryPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Son park yeri", systemImage: "car.fill")
                .font(.headline)

            if let latitude = point.latitude, let longitude = point.longitude {
                Text("\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))")
                    .font(.callout.monospacedDigit())

                if let url = URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)") {
                    Link(destination: url) {
                        Label("Yol tarifi al", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
            }

            Text(point.date, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
