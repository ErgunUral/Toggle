import SwiftUI
import Charts

struct BatteryHealthView: View {
    @Environment(GarageStore.self) private var store

    private var points: [HistoryPoint] {
        store.history.capacityPoints(lastDays: 90)
    }

    private var currentCapacity: Double? {
        store.snapshot.usableCapacityKWh
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BatteryCapacitySummary(
                    currentCapacity: currentCapacity,
                    points: points
                )
                BatteryCapacityChart(points: points)

                Text("Bu değer üretici tarafından sağlanan resmi batarya sağlık (SOH) yüzdesi değildir. Kalan enerji ve batarya yüzdesinden hesaplanan yaklaşık kullanılabilir kapasitedir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .glassCard()

                if points.isEmpty {
                    Text("Canlı telemetri kayıtları oluştukça kapasite trendi görünür.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Batarya sağlığı")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct BatteryCapacitySummary: View {
    let currentCapacity: Double?
    let points: [HistoryPoint]

    private var change: Double? {
        guard let first = points.first?.usableCapacityKWh,
              let last = points.last?.usableCapacityKWh else {
            return nil
        }
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kullanılabilir kapasite", systemImage: "battery.100percent")
                .font(.headline)

            Text(currentCapacity.map { "\($0.decimal(1)) kWh" } ?? "—")
                .font(.system(.title, design: .rounded).weight(.semibold))

            if let change {
                Text("90 günlük kayıt farkı: \(change >= 0 ? "+" : "")\(change.decimal(1)) kWh")
                    .font(.callout)
                    .foregroundStyle(change < -2 ? .orange : .secondary)
            } else {
                Text("Karşılaştırma için en az iki canlı kayıt gerekir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct BatteryCapacityChart: View {
    let points: [HistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Son 90 gün")
                .font(.headline)

            if points.isEmpty {
                ContentUnavailableView(
                    "Henüz kapasite ölçümü yok",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Canlı batarya ölçümleri geldikçe grafik oluşur.")
                )
                .frame(height: 220)
            } else {
                Chart(points) { point in
                    if let capacity = point.usableCapacityKWh {
                        LineMark(
                            x: .value("Zaman", point.date),
                            y: .value("Kapasite", capacity)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbol(.circle)
                    }
                }
                .chartYAxisLabel("kWh")
                .frame(height: 250)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
