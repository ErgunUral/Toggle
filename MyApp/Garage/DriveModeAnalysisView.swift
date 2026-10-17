import SwiftUI
import Charts

struct DriveModeAnalysisView: View {
    @Environment(GarageStore.self) private var store

    private var modeCounts: [(mode: String, count: Int)] {
        let modes = store.history.points
            .filter { $0.date >= Date.now.addingTimeInterval(-30 * 24 * 3600) }
            .compactMap(\.driveMode)

        let counts = Dictionary(grouping: modes, by: { $0 })
            .map { (mode: $0.key, count: $0.value.count) }

        return counts.sorted { $0.count > $1.count }
    }

    private var total: Int {
        modeCounts.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DriveModeSummary(modeCounts: modeCounts, total: total)
                DriveModeChart(modeCounts: modeCounts)

                Text("Analiz, uygulama açıkken alınan canlı telemetri kayıtlarına dayanır. Kayıt olmayan sürüşler dağılıma dahil edilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .glassCard()
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Sürüş modu analizi")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct DriveModeSummary: View {
    let modeCounts: [(mode: String, count: Int)]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Son 30 gün", systemImage: "speedometer")
                .font(.headline)

            if let primary = modeCounts.first, total > 0 {
                Text("En çok kullanılan: \(primary.mode)")
                    .font(.title3.weight(.semibold))
                Text("\(primary.count) kayıt · yüzde \((Double(primary.count) / Double(total) * 100).decimal())")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Henüz sürüş modu geçmişi yok.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct DriveModeChart: View {
    let modeCounts: [(mode: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mod dağılımı")
                .font(.headline)

            if modeCounts.isEmpty {
                ContentUnavailableView(
                    "Henüz kayıt yok",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Canlı sürüş modu kayıtları oluştukça grafik görünür.")
                )
                .frame(height: 220)
            } else {
                Chart(modeCounts, id: \.mode) { item in
                    BarMark(
                        x: .value("Mod", item.mode),
                        y: .value("Kayıt", item.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .top) {
                        Text("\(item.count)")
                            .font(.caption2)
                    }
                }
                .chartYAxisLabel("kayıt")
                .frame(height: 240)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
