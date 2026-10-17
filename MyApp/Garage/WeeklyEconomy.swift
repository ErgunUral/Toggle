import SwiftUI
import Charts

/// Bir haftalık (7 günlük kayan pencere) ekonomi puanı. Puan `PeriodSummary.economyScore` ile aynı
/// ölçeği kullanır; yeterli ölçülmüş mesafe yoksa `score` nil'dir.
nonisolated struct WeeklyEconomyScore: Identifiable, Sendable {
    /// Pencerenin başlangıcı.
    let start: Date
    let score: Double?
    let distanceKm: Double

    var id: Date { start }
}

nonisolated enum WeeklyEconomy {
    /// En eski hafta başta olacak şekilde, `now`da biten `weeks` adet 7 günlük pencere.
    /// Gezi hangi pencereye ait olduğu bitiş zamanına göre belirlenir.
    static func scores(from trips: [DerivedTrip], weeks: Int = 8, now: Date = .now) -> [WeeklyEconomyScore] {
        guard weeks > 0 else { return [] }
        let week: TimeInterval = 7 * 24 * 3600
        return (0..<weeks).reversed().map { index in
            let end = now.addingTimeInterval(-Double(index) * week)
            let start = end.addingTimeInterval(-week)
            let inWindow = trips.filter { $0.end > start && $0.end <= end }
            let summary = PeriodSummary(trips: inWindow)
            return WeeklyEconomyScore(start: start, score: summary.economyScore, distanceKm: summary.distanceKm)
        }
    }

    /// Puanı olan son iki hafta arasındaki fark (son − önceki). İkisi de yoksa nil.
    static func change(in weeks: [WeeklyEconomyScore]) -> Double? {
        let scored = weeks.compactMap(\.score)
        guard scored.count >= 2 else { return nil }
        return scored[scored.count - 1] - scored[scored.count - 2]
    }
}

/// Son haftaların ekonomi puanı eğilimi. Araç ivmelenme/frenleme verisi paylaşmadığından bu bir
/// "sürüş davranışı" puanı değil; yalnızca ölçülmüş batarya kullanımına dayanan tahmini bir ölçektir.
struct WeeklyEconomyCard: View {
    let trips: [DerivedTrip]

    private var weeks: [WeeklyEconomyScore] { WeeklyEconomy.scores(from: trips) }

    var body: some View {
        let weeks = weeks
        let change = WeeklyEconomy.change(in: weeks)

        VStack(alignment: .leading, spacing: 14) {
            Label("Haftalık ekonomi puanı", systemImage: "chart.bar.fill")
                .font(.headline)

            if weeks.contains(where: { $0.score != nil }) {
                if let change {
                    Label(
                        change >= 0.5 ? "Önceki haftadan +\(change.decimal()) puan"
                            : change <= -0.5 ? "Önceki haftadan \(change.decimal()) puan"
                            : "Önceki haftayla aynı",
                        systemImage: change >= 0.5 ? "arrow.up.right" : change <= -0.5 ? "arrow.down.right" : "equal"
                    )
                    .font(.subheadline)
                    .foregroundStyle(change >= 0.5 ? .green : change <= -0.5 ? .orange : .secondary)
                }

                Chart(weeks) { week in
                    if let score = week.score {
                        BarMark(
                            x: .value("Hafta", week.start, unit: .weekOfYear),
                            y: .value("Puan", score)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
            } else {
                Text("Puan için haftada en az \(PeriodSummary.minimumTrackedKm.decimal()) km ölçülmüş sürüş gerekir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Puan, 100 km'deki batarya kullanımından hesaplanır; aracın ivmelenme veya frenleme verisi olmadığı için sürüş tarzını ölçmez. Togg'un puanı değildir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
