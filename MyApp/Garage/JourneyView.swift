import SwiftUI
import Charts

/// Seyahatname gösterim aralığı (gün).
private enum JourneyRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, year = 365

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7 gün"
        case .month: "30 gün"
        case .quarter: "90 gün"
        case .year: "Yıl"
        }
    }
}

/// Seyahatname. Canlı modda bu cihazda biriken kayıtlardan, örnek modda örnek veriden çizer.
/// Canlı modda yalnızca ölçülmüş değerler (kilometre, batarya yüzdesi, sıcaklık, süre) ve aracın
/// bildirdiği ortalamalar gösterilir; enerji, tüketim ya da güç gibi tahminler gösterilmez.
struct JourneyView: View {
    @Environment(GarageStore.self) private var store
    @State private var range = JourneyRange.week

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if store.snapshot.isLive {
                    NavigationLink {
                        ServerAnalyticsView()
                    } label: {
                        Label("Sunucu analizleri", systemImage: "icloud.and.arrow.down")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .glassCard()
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
        let days = range.rawValue

        ServerRecordSection(isCharge: false, period: .monthly, limit: 5)
        let distances = history.dailyDistances(days: days)
        let batteryPoints = history.batteryPoints(lastDays: days)
        let trips = history.trips(lastDays: days)
        let charges = history.chargeSessions(lastDays: days)

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
            Picker("Aralık", selection: $range) {
                ForEach(JourneyRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            distanceChart(
                title: LocalizedStringKey("Son \(days) gün"),
                days: distances.days,
                footnote: distances.untrackedKm > 0
                    ? "\(distances.untrackedKm.decimal()) km, kayıt alınmayan aralıklara denk geldiği için günlere dağıtılmadı."
                    : "Mesafe, ardışık kilometre sayacı kayıtlarının farkından hesaplanır."
            )
            batteryChart(batteryPoints)
            summary(trips: trips, distances: distances, recordCount: history.points.count)
            WeeklyEconomyCard(trips: history.trips(lastDays: 8 * 7))
            tripList(trips)
            VStack(spacing: 12) {
                SectionTitle("Şarj oturumları")
                ChargeSessionList(sessions: charges)
            }
        }
    }

    private func summary(trips: [DerivedTrip], distances: HistoryStore.DailyDistances, recordCount: Int) -> some View {
        let total = distances.days.reduce(0) { $0 + $1.km }
        let longest = trips.map(\.distanceKm).max()
        // Ortalamalar aracın kendi bildirdiği "son şarjdan beri" değerleridir.
        let vehicle = store.snapshot.tripsAreLive ? store.snapshot.sinceCharge : nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                StatTile(title: "Kayıtlı mesafe", value: total.decimal(), unit: "km")
                StatTile(title: "Gezi", value: "\(trips.count)")
                StatTile(title: "En uzun gezi", value: longest.decimal(), unit: "km")
            }
            Divider()
            HStack(alignment: .top, spacing: 14) {
                StatTile(title: "Ort. tüketim (araç, son şarjdan)", value: vehicle?.average.decimal(1) ?? "—", unit: "kWh/100 km")
                StatTile(title: "Ort. hız (araç, son şarjdan)", value: vehicle?.averageSpeed.decimal() ?? "—", unit: "km/sa")
                StatTile(title: "Kayıt", value: "\(recordCount)")
            }
            Divider()
            periodStats(PeriodSummary(trips: trips))
        }
        .glassCard()
    }

    /// Seçili aralıktaki gezilerden bu cihazda hesaplanan özet ve ekonomi puanı.
    private func periodStats(_ period: PeriodSummary) -> some View {
        let duration = period.duration
        let hours = Int(duration / 3600)
        let minutes = Int(duration / 60) % 60
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                StatTile(title: "Sürüş süresi", value: hours > 0 ? "\(hours) sa \(minutes) dk" : "\(minutes) dk")
                StatTile(title: "Ort. hız (kayıtlı)", value: period.averageSpeedKmh?.decimal() ?? "—", unit: "km/sa")
            }
            HStack(alignment: .top, spacing: 14) {
                StatTile(title: "Batarya / 100 km", value: period.batteryPercentPer100Km?.decimal(1) ?? "—", unit: "%")
                StatTile(title: "Ekonomi puanı (tahmini)", value: period.economyScore?.decimal() ?? "—", unit: "/100")
            }
            Text("Puan, 100 km'de kullanılan batarya yüzdesinden hesaplanır (%\(PeriodSummary.bestPercentPer100Km.decimal()) ve altı 100, %\(PeriodSummary.worstPercentPer100Km.decimal()) ve üstü 0). Bu uygulamaya özgü tahmini bir ölçektir; en az \(PeriodSummary.minimumTrackedKm.decimal()) km batarya verili gezi gerekir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Gezi listesi

    @ViewBuilder private func tripList(_ trips: [DerivedTrip]) -> some View {
        VStack(spacing: 12) {
            SectionTitle("Geziler")
            if trips.isEmpty {
                Text("Bu aralıkta gezi bulunamadı. Gezi çıkarılabilmesi için sürüş sırasında uygulamanın açık olması gerekir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .glassCard()
            } else {
                let calendar = Calendar.current
                let groups = Dictionary(grouping: trips) { calendar.startOfDay(for: $0.start) }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.longDateText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            let dayTrips = groups[day] ?? []
                            ForEach(dayTrips) { trip in
                                NavigationLink {
                                    TripDetailView(trip: trip)
                                } label: {
                                    TripRow(trip: trip)
                                }
                                .buttonStyle(.plain)
                                if trip.id != dayTrips.last?.id { Divider() }
                            }
                        }
                        .glassCard()
                    }
                }
                Text("Geziler, kaydedilen kilometre sayacındaki artıştan çıkarılır; uygulama kapalıyken yapılan sürüşler ya da kısa geziler görünmeyebilir, başlangıç ve bitiş saatleri yaklaşıktır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
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
                .cornerRadius(days.count > 14 ? 2 : 6)
            }
            .chartXAxis {
                if days.count <= 7 {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                } else {
                    // Uzun aralıkta her gün yerine haftalık (yıllıkta aylık) etiket.
                    let monthly = days.count > 120
                    AxisMarks(values: .stride(by: monthly ? .month : .weekOfYear)) {
                        AxisGridLine()
                        AxisValueLabel(format: monthly ? .dateTime.month(.abbreviated) : .dateTime.day().month(.defaultDigits))
                    }
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

// MARK: - Gezi satırı

private struct TripRow: View {
    let trip: DerivedTrip

    private var durationText: String {
        let minutes = Int((trip.duration / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.side")
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.18), in: .circle)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(trip.start, format: .dateTime.hour().minute())) – \(Text(trip.end, format: .dateTime.hour().minute()))")
                    .font(.subheadline.weight(.medium))
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(trip.distanceKm.decimal(1)) km").font(.subheadline.monospacedDigit())
                Text(trip.batteryUsedPercent.map { "Batarya −\($0.decimal())%" } ?? "Batarya verisi yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

// MARK: - Gezi detayı

struct TripDetailView: View {
    @Environment(GarageStore.self) private var store
    let trip: DerivedTrip

    private var durationText: String {
        let minutes = Int((trip.duration / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
    }

    private var batteryText: String {
        guard let start = trip.startBattery, let end = trip.endBattery else { return "—" }
        return "%\((start * 100).decimal()) → %\((end * 100).decimal())"
    }

    var body: some View {
        let points = store.history.points(from: trip.start, to: trip.end).filter { $0.battery != nil }
        ScrollView {
            VStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(trip.start.shortDateTimeText) · \(durationText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            StatTile(title: "Mesafe", value: trip.distanceKm.decimal(1), unit: "km")
                            StatTile(title: "Süre", value: durationText)
                        }
                        GridRow {
                            StatTile(
                                title: "Batarya",
                                value: batteryText,
                                unit: trip.batteryUsedPercent.map { "(−\($0.decimal())%)" } ?? ""
                            )
                            StatTile(title: "Dış sıcaklık", value: trip.averageOutsideTemp.decimal(), unit: "°C")
                        }
                    }
                }
                .glassCard()

                if points.count >= 2 {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Batarya seviyesi").font(.headline)
                        Chart(points) { point in
                            if let battery = point.battery {
                                LineMark(
                                    x: .value("Zaman", point.date),
                                    y: .value("Batarya", battery * 100)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                PointMark(
                                    x: .value("Zaman", point.date),
                                    y: .value("Batarya", battery * 100)
                                )
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxisLabel("%")
                        .frame(height: 180)
                    }
                    .glassCard()
                }

                Text("Değerler cihazda kaydedilen ölçümlerden alınır. Gezi sınırları kayıt sıklığına bağlı olarak yaklaşıktır; enerji ya da tüketim tahmini yapılmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .navigationTitle("Gezi")
        .navigationBarTitleDisplayModeInline()
    }
}

#Preview {
    NavigationStack { JourneyView() }.environment(GarageStore())
}
