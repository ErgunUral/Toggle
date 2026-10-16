import SwiftUI
import MapKit

struct LocationView: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        NavigationStack {
            Group {
                if let coordinate = snapshot.coordinate {
                    map(snapshot: snapshot, coordinate: coordinate)
                } else {
                    ContentUnavailableView(
                        "Konum alınamadı",
                        systemImage: "location.slash",
                        description: Text("Araç son verisinde konum bilgisi yok.")
                    )
                    .background { AppBackground() }
                }
            }
            .navigationTitle("Konum")
            .navigationBarTitleDisplayModeInline()
        }
    }

    private func map(snapshot: VehicleSnapshot, coordinate: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 1800))) {
            Marker(snapshot.name, systemImage: "car.fill", coordinate: coordinate)
                .tint(Color.accentColor)
        }
        // Konum değişince harita yeni konumdan yeniden başlar.
        .id("\(coordinate.latitude),\(coordinate.longitude)")
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    snapshot.address ?? "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))",
                    systemImage: "mappin.and.ellipse"
                )
                .font(.headline)
                Text(updatedText(snapshot.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)") {
                    Link(destination: url) {
                        Label("Yol tarifi al", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .glassCard(cornerRadius: 30)
            .padding(.horizontal, 16)
        }
    }

    private func updatedText(_ date: Date?) -> String {
        guard let date else { return "Veri zamanı bilinmiyor. Konum aracın şu anki konumu olmayabilir." }
        return "Son araç verisinin zamanına aittir: \(date.relativeText)."
    }
}

extension View {
    @ViewBuilder func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#Preview {
    LocationView().environment(GarageStore())
}
