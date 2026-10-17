import SwiftUI
import Charts

struct TirePressureHistoryView: View {
    @Environment(GarageStore.self) private var store

    private var points: [HistoryPoint] {
        store.history.tirePressurePoints(lastDays: 30)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TirePressureChart(points: points)

                if points.isEmpty {
                    Text("Canlı telemetri kaydı oluştukça son 30 günlük basınç geçmişi burada görünecek.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .glassCard()
                } else if let latest = points.last {
                    TirePressureLatestValues(point: latest)
                }

                Text("Kayıtlar uygulama açıkken ve canlı veri yenilendiğinde oluşturulur. Geçmiş veriler cihazda saklanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Lastik basıncı geçmişi")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct TirePressureChart: View {
    let points: [HistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Son 30 gün")
                .font(.headline)

            if points.isEmpty {
                ContentUnavailableView(
                    "Henüz ölçüm yok",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Canlı lastik basıncı ölçümleri geldikçe grafik oluşur.")
                )
                .frame(height: 220)
            } else {
                Chart {
                    ForEach(points) { point in
                        if let value = point.tireFrontLeftPSI {
                            LineMark(
                                x: .value("Zaman", point.date),
                                y: .value("PSI", value)
                            )
                            .foregroundStyle(by: .value("Lastik", "Sol ön"))
                            .symbol(.circle)
                        }
                        if let value = point.tireFrontRightPSI {
                            LineMark(
                                x: .value("Zaman", point.date),
                                y: .value("PSI", value)
                            )
                            .foregroundStyle(by: .value("Lastik", "Sağ ön"))
                            .symbol(.circle)
                        }
                        if let value = point.tireRearLeftPSI {
                            LineMark(
                                x: .value("Zaman", point.date),
                                y: .value("PSI", value)
                            )
                            .foregroundStyle(by: .value("Lastik", "Sol arka"))
                            .symbol(.circle)
                        }
                        if let value = point.tireRearRightPSI {
                            LineMark(
                                x: .value("Zaman", point.date),
                                y: .value("PSI", value)
                            )
                            .foregroundStyle(by: .value("Lastik", "Sağ arka"))
                            .symbol(.circle)
                        }

                        RuleMark(y: .value("Önerilen alt sınır", 31))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(dash: [5, 4]))
                    }
                }
                .chartYScale(domain: 25...45)
                .chartYAxisLabel("PSI")
                .frame(height: 260)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct TirePressureLatestValues: View {
    let point: HistoryPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Son ölçüm")
                .font(.headline)

            let values: [(String, Double?)] = [
                ("Sol ön", point.tireFrontLeftPSI),
                ("Sağ ön", point.tireFrontRightPSI),
                ("Sol arka", point.tireRearLeftPSI),
                ("Sağ arka", point.tireRearRightPSI)
            ]

            ForEach(values, id: \.0) { item in
                LabeledContent(item.0, value: item.1.map { "\($0.decimal(1)) PSI" } ?? "—")
            }

            Text(point.date, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
