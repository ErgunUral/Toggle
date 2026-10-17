import SwiftUI

struct HomeView: View {
    @Environment(GarageStore.self) private var store
    @State private var showSmartAlerts = false

    private var snapshot: VehicleSnapshot {
        store.snapshot
    }

    private var dataSourceText: String {
        if store.isUsingCachedData {
            return "Önbellek verisi"
        }
        return snapshot.isLive ? "Canlı araç verisi" : "Demo verisi"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LiveDataHeader(
                        name: snapshot.name,
                        source: dataSourceText,
                        updatedAt: snapshot.updatedAt,
                        fetchedAt: store.lastRefreshAt
                    )

                    if let message = store.message {
                        LiveDataBanner(message: message)
                    }

                    LiveVehicleOverview(
                        snapshot: snapshot,
                        imageName: store.color.imageName
                    )

                    LiveAIEntry(snapshot: snapshot)

                    if snapshot.isLive {
                        LiveVehicleControlsEntry()
                    }

                    LiveDataSection("Araç bilgileri", symbol: "car.side.fill") {
                        LiveDataRow("Model", value: snapshot.model)
                        LiveDataRow("Versiyon", value: snapshot.edition)
                        LiveDataRow("Üretim yılı", value: "\(snapshot.year)")
                        LiveDataRow("VIN", value: snapshot.vin)
                        LiveDataRow("Plaka", value: snapshot.plate ?? "—")
                        LiveDataRow("Üretici", value: snapshot.manufacturer ?? "—")
                        LiveDataRow("Sahiplik", value: snapshot.ownerType ?? "—")
                        LiveDataRow(
                            "Yazılım",
                            value: snapshot.softwareVersion ?? "—"
                        )
                        LiveDataRow(
                            "Anahtar paylaşımı",
                            value: snapshot.keySharingEnabled.map { $0 ? "Açık" : "Kapalı" } ?? "—"
                        )
                    }

                    LiveDataSection("Enerji ve şarj", symbol: "bolt.batteryblock.fill") {
                        LiveDataMetricGrid {
                            LiveMetric(
                                title: "Batarya",
                                value: snapshot.battery.map { "\(($0 * 100).decimal())%" } ?? "—",
                                symbol: "battery.75percent"
                            )
                            LiveMetric(
                                title: "Menzil",
                                value: snapshot.range.map { "\($0.decimal()) km" } ?? "—",
                                symbol: "road.lanes"
                            )
                            LiveMetric(
                                title: "Kalan enerji",
                                value: snapshot.batteryEnergyKWh.map { "\($0.decimal(1)) kWh" } ?? "—",
                                symbol: "bolt.fill"
                            )
                            LiveMetric(
                                title: "Tahmini kapasite",
                                value: snapshot.usableCapacityKWh.map { "\($0.decimal(1)) kWh" } ?? "—",
                                symbol: "chart.bar.fill"
                            )
                        }

                        LiveDataRow(
                            "Şarj durumu",
                            value: snapshot.isCharging.map { $0 ? "Şarj oluyor" : "Şarj olmuyor" } ?? "—",
                            valueColor: snapshot.isCharging == true ? .green : nil
                        )
                        LiveDataRow(
                            "12 V akü",
                            value: snapshot.auxBattery.map { "\(($0 * 100).decimal())%" } ?? "—",
                            valueColor: AuxBattery.isLow(snapshot.auxBattery) ? .orange : nil
                        )
                        LiveDataRow(
                            "İnternet kullanımı",
                            value: "\(snapshot.internetUsedGB.decimal(1)) / \(snapshot.internetQuotaGB.decimal(1)) GB"
                        )
                    }

                    LiveDataSection("İklim ve kabin", symbol: "fan.fill") {
                        LiveDataMetricGrid {
                            LiveMetric(
                                title: "Dış sıcaklık",
                                value: snapshot.outside.map { "\($0.decimal()) °C" } ?? "—",
                                symbol: "sun.max.fill"
                            )
                            LiveMetric(
                                title: "Kabin sıcaklığı",
                                value: snapshot.inside.map { "\($0.decimal()) °C" } ?? "—",
                                symbol: "thermometer.medium"
                            )
                            LiveMetric(
                                title: "Hedef sıcaklık",
                                value: "\(snapshot.targetTemperature) °C",
                                symbol: "target"
                            )
                            LiveMetric(
                                title: "Klima",
                                value: snapshot.climateOn ? "Açık" : "Kapalı",
                                symbol: "fan.fill"
                            )
                        }

                        LiveDataRow("Klima modu", value: snapshot.climateMode.displayText)
                        LiveDataRow("Ön cam buğu çözme", value: snapshot.defrost ? "Açık" : "Kapalı")
                        LiveDataRow("Direksiyon ısıtma", value: snapshot.steeringHeat ? "Açık" : "Kapalı")
                        LiveDataRow("Sürücü koltuğu ısıtma", value: snapshot.driverSeatHeat ? "Açık" : "Kapalı")
                        LiveDataRow("Yolcu koltuğu ısıtma", value: snapshot.passengerSeatHeat ? "Açık" : "Kapalı")
                    }

                    LiveDataSection("Güvenlik ve erişim", symbol: "lock.shield.fill") {
                        LiveDataRow(
                            "Kapılar",
                            value: snapshot.doorsLocked ? "Kilitli" : "Açık",
                            valueColor: snapshot.doorsLocked ? .green : .orange
                        )
                        LiveDataRow(
                            "Bagaj",
                            value: snapshot.trunkOpen ? "Açık" : "Kapalı",
                            valueColor: snapshot.trunkOpen ? .orange : .green
                        )
                        LiveDataRow(
                            "Fren sistemi",
                            value: snapshot.brakeWarning.map { $0 ? "Uyarı var" : "Normal" } ?? "—",
                            valueColor: snapshot.brakeWarning == true ? .red : .green
                        )
                        LiveDataRow(
                            "Araç sistemi",
                            value: snapshot.engineWarning.map { $0 ? "Uyarı var" : "Normal" } ?? "—",
                            valueColor: snapshot.engineWarning == true ? .red : .green
                        )
                    }

                    LiveDataSection("Lastikler", symbol: "circle.grid.2x2.fill") {
                        TireLiveRow(
                            title: "Sol ön",
                            pressure: snapshot.tires.frontLeft,
                            temperature: snapshot.tireTemperatures.frontLeft
                        )
                        TireLiveRow(
                            title: "Sağ ön",
                            pressure: snapshot.tires.frontRight,
                            temperature: snapshot.tireTemperatures.frontRight
                        )
                        TireLiveRow(
                            title: "Sol arka",
                            pressure: snapshot.tires.rearLeft,
                            temperature: snapshot.tireTemperatures.rearLeft
                        )
                        TireLiveRow(
                            title: "Sağ arka",
                            pressure: snapshot.tires.rearRight,
                            temperature: snapshot.tireTemperatures.rearRight
                        )
                    }

                    LiveDataSection("Sürüş", symbol: "speedometer") {
                        LiveDataRow("Sürüş modu", value: snapshot.driveMode ?? "—")
                        LiveDataRow(
                            "Kilometre",
                            value: snapshot.odometer.map { "\($0.decimal()) km" } ?? "—"
                        )

                        LiveTripCard(title: "Mevcut yolculuk", trip: snapshot.currentTrip)
                        LiveTripCard(title: "Son şarjdan beri", trip: snapshot.sinceCharge)
                        if let myTrip = snapshot.myTrip {
                            LiveTripCard(title: "Yolculuğum", trip: myTrip)
                        }
                    }

                    LiveDataSection("Konum", symbol: "location.fill") {
                        LiveDataRow("Adres", value: snapshot.address ?? "—")
                        LiveDataRow(
                            "Koordinat",
                            value: snapshot.coordinate.map {
                                "\($0.latitude.decimal(5)), \($0.longitude.decimal(5))"
                            } ?? "—"
                        )
                    }

                    LiveDataSection("Akıllı uyarılar", symbol: "sparkles") {
                        SmartVehicleAlertsCard(snapshot: snapshot, showsEmptyState: true)
                            .padding(.top, -8)
                            .padding(.horizontal, -18)
                            .padding(.bottom, -18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .navigationTitle("Araç")
            .navigationSubtitle(dataSourceText)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Akıllı bildirimler", systemImage: "bell.badge.fill") {
                        showSmartAlerts = true
                    }

                    Button("Yenile", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                    .disabled(store.isRefreshing)
                }
            }
            .refreshable {
                await store.refresh()
            }
            .sheet(isPresented: $showSmartAlerts) {
                NavigationStack {
                    ScrollView {
                        SmartVehicleAlertsCard(snapshot: snapshot, showsEmptyState: true)
                            .padding(16)
                    }
                    .background { AppBackground() }
                    .navigationTitle("Akıllı bildirimler")
                }
            }
        }
    }
}

private struct LiveDataHeader: View {
    let name: String
    let source: String
    let updatedAt: Date?
    let fetchedAt: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandLockup(showsTagline: false, compact: true)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(source == "Canlı araç verisi" ? .green : .secondary)

                Text(fetchedAt.map { "Son sorgu: \($0.relativeText)" } ?? "Son sorgu bilinmiyor")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let updatedAt {
                    Text("Telemetri: \(updatedAt.relativeText)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(source), son sorgu \(fetchedAt?.relativeText ?? "bilinmiyor"), telemetri \(updatedAt?.relativeText ?? "bilinmiyor")")
    }
}

private struct LiveDataBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}

private struct LiveVehicleOverview: View {
    let snapshot: VehicleSnapshot
    let imageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text("\(snapshot.model) · \(snapshot.edition)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label(
                        snapshot.isLive ? "Telemetri bağlı" : "Canlı bağlantı bekleniyor",
                        systemImage: snapshot.isLive
                            ? "antenna.radiowaves.left.and.right"
                            : "icloud.slash"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isLive ? .green : .secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(.secondary.opacity(0.16), lineWidth: 7)

                    Circle()
                        .trim(from: 0, to: min(max(snapshot.battery ?? 0, 0), 1))
                        .stroke(
                            snapshot.batteryColor,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(snapshot.battery.map { "\(($0 * 100).decimal())%" } ?? "—")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .frame(width: 66, height: 66)
            }

            VehicleImageView(name: imageName)
                .frame(height: 145)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(snapshot.model), \(snapshot.edition)")

            HStack(spacing: 8) {
                LiveSummaryPill(
                    title: "Menzil",
                    value: snapshot.range.map { "\($0.decimal()) km" } ?? "—",
                    symbol: "bolt.fill"
                )
                LiveSummaryPill(
                    title: "Kabin",
                    value: snapshot.inside.map { "\($0.decimal()) °C" } ?? "—",
                    symbol: "thermometer.medium"
                )
                LiveSummaryPill(
                    title: "Şarj",
                    value: snapshot.isCharging == true ? "Aktif" : "Pasif",
                    symbol: "ev.charger"
                )
            }
        }
        .glassCard(cornerRadius: 26)
    }
}

private struct LiveSummaryPill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveAIEntry: View {
    let snapshot: VehicleSnapshot

    var body: some View {
        NavigationLink {
            AIGarageAssistantView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(ToggGarageBrand.primaryGradient, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Canlı verini AI ile yorumla")
                        .font(.subheadline.weight(.bold))
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var prompt: String {
        if snapshot.brakeWarning == true || snapshot.engineWarning == true {
            return "Araçta dikkat edilmesi gereken bir uyarı var."
        }

        if let battery = snapshot.battery, battery < 0.25 {
            return "Düşük batarya için menzil ve şarj planı oluştur."
        }

        return "Batarya, enerji, iklim ve sürüş verilerini sor."
    }
}

private struct LiveVehicleControlsEntry: View {
    var body: some View {
        NavigationLink {
            DigitalKeyView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.trianglebadge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(ToggGarageBrand.signal, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Araç kontrolleri")
                        .font(.headline)
                    Text("Kapı, bagaj ve cam komutlarını yönet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dijital anahtar ve araç komutlarını açar")
    }
}

private struct LiveDataSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.bold))

            content()
        }
        .glassCard(cornerRadius: 22)
    }
}

private struct LiveDataRow: View {
    let title: String
    let value: String
    let valueColor: Color?

    init(_ title: String, value: String, valueColor: Color? = nil) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LiveDataMetricGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            content()
        }
    }
}

private struct LiveMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}

private struct TireLiveRow: View {
    let title: String
    let pressure: Double?
    let temperature: Double?

    var body: some View {
        HStack {
            Image(systemName: "circle.grid.2x2.fill")
                .foregroundStyle(pressureColor)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(pressure.map { "\($0.decimal(1)) PSI" } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(pressureColor)

            Text(temperature.map { "· \($0.decimal(1)) °C" } ?? "· —")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pressureColor: Color {
        guard let pressure else { return .secondary }
        return pressure < 31 ? .orange : .green
    }
}

private struct LiveTripCard: View {
    let title: String
    let trip: TripStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                LiveTripValue(title: "Mesafe", value: "\(trip.distance.decimal(1)) km")
                LiveTripValue(title: "Tüketim", value: "\(trip.energy.decimal(1)) kWh")
                LiveTripValue(title: "Ortalama", value: "\(trip.average.decimal(1)) kWh/100 km")
            }

            if !trip.note.isEmpty {
                Text(trip.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
    }
}

private struct LiveTripValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension VehicleSnapshot {
    var batteryColor: Color {
        switch battery ?? 0 {
        case 0..<0.2: .red
        case 0.2..<0.5: .orange
        default: .green
        }
    }
}

private extension ClimateMode {
    var displayText: String {
        switch self {
        case .auto: "Otomatik"
        case .heat: "Isıtma"
        case .cool: "Soğutma"
        }
    }
}
