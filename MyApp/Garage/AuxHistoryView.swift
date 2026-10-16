import SwiftUI
import Charts

/// 12 V yardımcı akü için ortak eşik. Bu değerin altında ya da eşitinde akü düşük sayılır.
enum AuxBattery {
    static let lowThreshold = 0.65

    static func isLow(_ level: Double?) -> Bool {
        guard let level else { return false }
        return level <= lowThreshold
    }
}

/// 12 V akü ölçüm geçmişi. Yalnızca bu cihazda, uygulama açıkken alınan kayıtları gösterir.
struct AuxHistoryView: View {
    @Environment(GarageStore.self) private var store
    @State private var days = 7

    var body: some View {
        let points = store.history.auxBatteryPoints(lastDays: days)
        ScrollView {
            VStack(spacing: 22) {
                Picker("Aralık", selection: $days) {
                    Text("7 gün").tag(7)
                    Text("30 gün").tag(30)
                    Text("90 gün").tag(90)
                }
                .pickerStyle(.segmented)

                if points.count < 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Veri biriktikçe dolacak", systemImage: "minus.plus.batteryblock")
                            .font(.headline)
                        Text("12 V akü ölçümleri uygulama açıldıkça bu cihazda kaydedilir. Bu aralıkta \(points.count) ölçüm var; grafik için en az 2 ölçüm gerekir.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                } else {
                    summary(points)
                    chart(points)
                }

                Text("Araç uyurken kesintisiz ölçüm ya da otomatik uyanma yoktur; kayıtsız aralıklar düz çizgiyle birleşir. %\((AuxBattery.lowThreshold * 100).decimal()) ve altı düşük sayılır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .navigationTitle("12 V akü geçmişi")
        .navigationBarTitleDisplayModeInline()
    }

    private func summary(_ points: [HistoryPoint]) -> some View {
        let levels = points.compactMap(\.auxBattery)
        let latest = levels.last
        return HStack(alignment: .top, spacing: 14) {
            StatTile(title: "Son", value: latest.map { ($0 * 100).decimal() } ?? "—", unit: "%")
            StatTile(title: "En düşük", value: levels.min().map { ($0 * 100).decimal() } ?? "—", unit: "%")
            StatTile(title: "En yüksek", value: levels.max().map { ($0 * 100).decimal() } ?? "—", unit: "%")
        }
        .glassCard()
    }

    private func chart(_ points: [HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Doluluk").font(.headline)
            Chart {
                ForEach(points) { point in
                    if let level = point.auxBattery {
                        LineMark(
                            x: .value("Zaman", point.date),
                            y: .value("Doluluk", level * 100)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                }
                RuleMark(y: .value("Düşük eşiği", AuxBattery.lowThreshold * 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
            .frame(height: 200)
        }
        .glassCard()
    }
}

#Preview {
    NavigationStack { AuxHistoryView() }.environment(GarageStore())
}
