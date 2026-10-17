import SwiftUI
import MapKit

struct LocationView: View {
    @Environment(GarageStore.self) private var store
    /// Canlı konumun ters coğrafi kodlamayla bulunan adresi.
    @State private var resolvedAddress: String?

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
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            guard snapshot.address == nil else { return }
            resolvedAddress = nil
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            // Adres bulunamazsa koordinat gösterilmeye devam eder.
            let item = try? await request.mapItems.first
            resolvedAddress = item?.address?.shortAddress ?? item?.name
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    snapshot.address ?? resolvedAddress ?? "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))",
                    systemImage: "mappin.and.ellipse"
                )
                .font(.headline)
                Text(updatedText(snapshot.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // dirflg=w yürüyüş, d sürüş. Başlangıç noktasını (kullanıcı konumu) Haritalar belirler;
                // uygulama konum izni istemez.
                if let url = URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d") {
                    Link(destination: url) {
                        Label("Yol tarifi al", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                if let url = URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=w") {
                    Link(destination: url) {
                        Label("Araca yürüyerek git", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
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
