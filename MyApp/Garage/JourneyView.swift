import SwiftUI
import Charts

/// Seyahatname gösterim aralığı (gün).
private enum JourneyRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7 gün"
        case .month: "30 gün"
        case .quarter: "90 gün"
        }
    }
}

/// Seyahatname. Canlı modda bu cihazda biriken kayıtlardan, örnek modda örnek veriden çizer.
struct JourneyView: View {
    @Environment(GarageStore.self) private var store
    @State private var range = JourneyRange.week

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
        let days = range.rawValue
        let capacity = store.snapshot.usableCapacityKWh
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
            summary(trips: trips, distances: distances, recordCount: history.points.count, capacity: capacity)
            tripList(trips, capacity: capacity)
            VStack(spacing: 12) {
                SectionTitle("Şarj oturumları")
                ChargeSessionList(sessions: charges, capacityKWh: capacity)
            }
        }
    }

    private func summary(trips: [DerivedTrip], distances: HistoryStore.DailyDistances, recordCount: Int, capacity: Double?) -> some View {
        let total = distances.days.reduce(0) { $0 + $1.km }
        let longest = trips.map(\.distanceKm).max()
        let speeds = trips.compactMap(\.averageSpeedKmh)
        let averageSpeed = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                StatTile(title: "Kayıtlı mesafe", value: total.decimal(), unit: "km")
                StatTile(title: "Gezi", value: "\(trips.count)")
                StatTile(title: "En uzun gezi", value: longest.decimal(), unit: "km")
            }
            Divider()
            HStack(alignment: .top, spacing: 14) {
                StatTile(
                    title: "Ort. tüketim (geziler)",
                    value: TripDeriver.averageConsumption(of: trips, capacityKWh: capacity).decimal(1),
                    unit: "kWh/100 km"
                )
                StatTile(title: "Ort. hız", value: averageSpeed.decimal(), unit: "km/sa")
                StatTile(title: "Kayıt", value: "\(recordCount)")
            }
        }
        .glassCard()
    }

    // MARK: Gezi listesi

    @ViewBuilder private func tripList(_ trips: [DerivedTrip], capacity: Double?) -> some View {
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
                                    TripDetailView(trip: trip, capacityKWh: capacity)
                                } label: {
                                    TripRow(trip: trip, capacityKWh: capacity)
                                }
                                .buttonStyle(.plain)
                                if trip.id != dayTrips.last?.id { Divider() }
                            }
                        }
                        .glassCard()
                    }
                }
                Text("Geziler, kilometre sayacındaki artıştan türetilir; uygulama kapalıyken yapılan sürüşler ya da kısa geziler görünmeyebilir.")
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
                    // Uzun aralıkta her gün yerine haftalık etiket.
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
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
    let capacityKWh: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.side")
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.18), in: .circle)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(trip.start, format: .dateTime.hour().minute())) – \(Text(trip.end, format: .dateTime.hour().minute()))")
                    .font(.subheadline.weight(.medium))
                Text(trip.batteryUsedPercent.map { "Batarya −\($0.decimal())%" } ?? "Batarya verisi yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(trip.distanceKm.decimal(1)) km").font(.subheadline.monospacedDigit())
                Text(trip.consumption(capacityKWh: capacityKWh).map { "\($0.decimal(1)) kWh/100 km" } ?? "—")
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
    let capacityKWh: Double?

    private var durationText: String {
        let minutes = Int((trip.duration / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
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
                            StatTile(title: "Ort. hız", value: trip.averageSpeedKmh.decimal(), unit: "km/sa")
                        }
                        GridRow {
                            StatTile(
                                title: "Batarya",
                                value: batteryText,
                                unit: trip.batteryUsedPercent.map { "(−\($0.decimal())%)" } ?? ""
                            )
                            StatTile(title: "Dış sıcaklık", value: trip.averageOutsideTemp.decimal(), unit: "°C")
                        }
                        GridRow {
                            StatTile(title: "Tahmini enerji", value: trip.energyKWh(capacityKWh: capacityKWh).decimal(1), unit: "kWh")
                            StatTile(title: "Tüketim", value: trip.consumption(capacityKWh: capacityKWh).decimal(1), unit: "kWh/100 km")
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

                Text("Enerji ve tüketim, batarya yüzdesi farkından ve tahmini kullanılabilir kapasiteden hesaplanır. Araç yüzdeyi tam sayı olarak bildirdiğinden kısa gezilerde (\(Int(TripDeriver.minimumDistanceForConsumptionKm)) km altı) tüketim gösterilmez. Gezi sınırları kayıt sıklığına bağlı olarak yaklaşıktır.")
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

    private var batteryText: String {
        guard let start = trip.startBattery, let end = trip.endBattery else { return "—" }
        return "%\((start * 100).decimal()) → %\((end * 100).decimal())"
    }
}

#Preview {
    NavigationStack { JourneyView() }.environment(GarageStore())
}
