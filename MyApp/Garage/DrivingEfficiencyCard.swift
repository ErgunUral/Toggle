import SwiftUI

struct DrivingEfficiencyCard: View {
    let trips: [DerivedTrip]

    private var measuredTrips: [DerivedTrip] {
        trips.filter { $0.distanceKm > 0 && $0.batteryUsedPercent != nil }
    }

    private var averageConsumption: Double? {
        guard !measuredTrips.isEmpty else { return nil }
        let values = measuredTrips.compactMap { trip -> Double? in
            guard let used = trip.batteryUsedPercent else { return nil }
            return used / trip.distanceKm * 100
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var score: Int? {
        guard let averageConsumption else { return nil }
        let normalized = (35 - averageConsumption) / 25 * 100
        return min(100, max(0, Int(normalized.rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sürüş verimliliği", systemImage: "leaf.fill")
                .font(.headline)

            if let score, let averageConsumption {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundStyle(scoreColor(score))
                    Text("/ 100")
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(score), total: 100)
                    .tint(scoreColor(score))

                Text("Ortalama batarya kullanımı: %\(averageConsumption.decimal(1)) / 100 km")
                    .font(.subheadline)
            } else {
                Label("Veri biriktikçe puan oluşacak", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline)
                Text("En az iki ölçülmüş sürüş gerektiğinden henüz hesaplama yapılamıyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(measuredTrips.count) ölçülmüş sürüş analiz edildi. Puan resmi tüketim veya servis teşhisi değildir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: .green
        case 55..<80: .orange
        default: .red
        }
    }
}
