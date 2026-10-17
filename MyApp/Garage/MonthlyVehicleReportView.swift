import SwiftUI
import Charts

struct MonthlyVehicleReportView: View {
    @Environment(GarageStore.self) private var store

    private var daily: HistoryStore.DailyDistances {
        store.history.dailyDistances(days: 30)
    }

    private var totalDistance: Double {
        daily.days.map(\.km).reduce(0, +)
    }

    private var activeDays: Int {
        daily.days.filter { $0.km > 0.1 }.count
    }

    private var averageDailyDistance: Double {
        guard activeDays > 0 else { return 0 }
        return totalDistance / Double(activeDays)
    }

    private var trips: [DerivedTrip] {
        store.history.trips(lastDays: 30)
    }

    private var batteryUsed: Double? {
        let values = trips.compactMap(\.batteryUsedPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryGrid

                VStack(alignment: .leading, spacing: 12) {
                    Label("Günlük mesafe", systemImage: "chart.bar.fill")
                        .font(.headline)

                    if totalDistance > 0 {
                        Chart(daily.days) { day in
                            BarMark(
                                x: .value("Gün", day.date, unit: .day),
                                y: .value("Kilometre", day.km)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                        }
                        .frame(height: 190)
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                    } else {
                        ContentUnavailableView(
                            "Henüz rapor yok",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Sürüş verileri biriktikçe aylık grafik oluşacak.")
                        )
                        .frame(height: 190)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Yorum", systemImage: "lightbulb")
                        .font(.headline)
                    Text(reportComment)
                        .font(.subheadline)
                    Text("Rapor yalnızca uygulama açıkken kaydedilen yerel ölçümlere dayanır; eksik günler gerçek kullanımı tam yansıtmayabilir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Aylık rapor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                StatTile(title: "Toplam mesafe", value: totalDistance.decimal(1), unit: "km")
                StatTile(title: "Aktif gün", value: "\(activeDays)", unit: "gün")
            }
            GridRow {
                StatTile(title: "Günlük ortalama", value: averageDailyDistance.decimal(1), unit: "km")
                StatTile(title: "Sürüş sayısı", value: "\(trips.count)")
            }
            if let batteryUsed {
                GridRow {
                    StatTile(title: "Tahmini batarya", value: batteryUsed.decimal(1), unit: "%")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var reportComment: String {
        if totalDistance == 0 {
            return "Henüz yorum üretmek için yeterli yerel sürüş kaydı yok."
        }
        if averageDailyDistance < 15 {
            return "Bu ay daha çok kısa mesafeli kullanım görülüyor."
        }
        if averageDailyDistance > 60 {
            return "Bu ay uzun mesafeli kullanım öne çıkıyor."
        }
        return "Bu ay düzenli ve dengeli bir kullanım paterni görülüyor."
    }
}
