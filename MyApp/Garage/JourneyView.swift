import SwiftUI
import Charts

/// Seyahatname. Canlı modda bu cihazda biriken kayıtlardan, örnek modda örnek veriden çizer.
struct JourneyView: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if store.snapshot.isLive {
                    liveContent
                } else {
                    sampleContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .navigationTitle("Seyahatname")
        .navigationBarTitleDisplayModeInline()
    }

    // MARK: Canlı

    @ViewBuilder private var liveContent: some View {
        let history = store.history
        let distances = history.dailyDistances()
        let batteryPoints = history.batteryPoints()

        if history.points.count < 2 {
            VStack(alignment: .leading, spacing: 8) {
                Label("Veri biriktikçe dolacak", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Text("Uygulama açıldıkça araç verisi bu cihazda kaydedilir. Şu an \(history.points.count) kayıt var; grafikler için en az 2 kayıt gerekir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
        } else {
            distanceChart(
                title: "Son 7 gün",
                days: distances.days,
                footnote: distances.untrackedKm > 0
                    ? "\(distances.untrackedKm.decimal()) km, kayıt alınmayan aralıklara denk geldiği için günlere dağıtılmadı."
                    : "Mesafe, ardışık kilometre sayacı kayıtlarının farkından hesaplanır."
            )
            batteryChart(batteryPoints)
            HStack(spacing: 14) {
                StatTile(title: "Kayıtlı mesafe", value: distances.days.reduce(0) { $0 + $1.km }.decimal(), unit: "km")
                StatTile(title: "Ort. tüketim", value: store.snapshot.sinceCharge.average.decimal(1), unit: "kWh/100 km")
                StatTile(title: "Kayıt", value: "\(history.points.count)")
            }
            .glassCard()
        }
    }

    private func batteryChart(_ points: [HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Batarya seviyesi").font(.headline)
            Chart(points) { point in
                if let battery = point.battery {
                    LineMark(
                        x: .value("Zaman", point.date),
                        y: .value("Batarya", battery * 100)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
            .frame(height: 180)
            Text("Kayıtlar yalnızca uygulama açıkken alınır; kayıtsız aralıklar düz çizgiyle birleşir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    // MARK: Örnek

    @ViewBuilder private var sampleContent: some View {
        distanceChart(title: "Son 7 gün · örnek veri", days: SampleData.weeklyDrives, footnote: nil)
        HStack(spacing: 14) {
            StatTile(title: "Toplam", value: SampleData.weeklyDrives.reduce(0) { $0 + $1.km }.decimal(), unit: "km")
            StatTile(title: "Ort. tüketim", value: store.snapshot.sinceCharge.average.decimal(1), unit: "kWh/100 km")
        }
        .glassCard()
    }

    // MARK: Ortak

    private func distanceChart(title: LocalizedStringKey, days: [DailyDrive], footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Chart(days) { drive in
                BarMark(
                    x: .value("Gün", drive.date, unit: .day),
                    y: .value("Mesafe", drive.km)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxisLabel("km")
            .frame(height: 200)
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }
}

#Preview {
    NavigationStack { JourneyView() }.environment(GarageStore())
}
