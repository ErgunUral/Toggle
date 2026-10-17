import SwiftUI

struct ChargeView: View {
    @Environment(GarageStore.self) private var store
    @State private var start = 20.0
    @State private var target = 80.0
    @State private var capacity = 88.5
    @State private var price = 10.0

    private var chargeStatusText: String {
        switch store.snapshot.isCharging {
        case true: "Şarj oluyor"
        case false: "Şarj olmuyor"
        case nil: "Şarj durumu okunamadı"
        }
    }

    private var energy: Double { max(0, target - start) / 100 * capacity }
    private var cost: Double { energy * price }
    /// AC 11 kW, saat cinsinden.
    private var acHours: Double { energy / 11 }
    /// DC 150 kW tepe güç; ortalama %70 verimle dakika cinsinden.
    private var dcMinutes: Double { energy / (150 * 0.7) * 60 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    BrandPageHeader(
                        title: "Şarj merkezi",
                        subtitle: "Enerjiyi planla, maliyeti ve menzili izle",
                        symbol: "bolt.fill"
                    )

                    statusCard
                    // Planlayıcının çıktıları (ücret, AC/DC süreleri) varsayıma dayandığından canlı modda gösterilmez.
                    if store.snapshot.isLive {
                        HistoricalChargePlannerCard(
                            snapshot: store.snapshot,
                            sessions: store.history.chargeSessions(lastDays: 90)
                        )
                        SmartChargingSuggestionCard(snapshot: store.snapshot)
                        LiveChargeEstimateCard(snapshot: store.snapshot)
                        NavigationLink {
                            BatteryHealthView()
                        } label: {
                            Label("Batarya sağlığı ve kapasite trendi", systemImage: "battery.100percent")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .glassCard()
                        }
                        .buttonStyle(.plain)
                        ServerRecordSection(isCharge: true, period: .monthly, limit: 5)
                        liveSessions
                    } else {
                        planner
                        sessions
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .navigationTitle("Şarj")
        }
    }

    private var statusCard: some View {
        HStack(spacing: 20) {
            ZStack {
                RingGauge(value: store.snapshot.battery ?? 0, lineWidth: 12)
                Image(systemName: "bolt.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.snapshot.battery.map { ($0 * 100).decimal() } ?? "—")%")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                Text("\(chargeStatusText) · \(store.snapshot.range.decimal()) km menzil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Şarj durumu")
            .accessibilityValue("\(store.snapshot.battery.map { ($0 * 100).decimal() } ?? "—") yüzde pil, \(chargeStatusText), \(store.snapshot.range.decimal()) kilometre menzil")
    }

    private var planner: some View {
        VStack(spacing: 12) {
            SectionTitle("Şarj planlayıcı")
            VStack(alignment: .leading, spacing: 16) {
                slider("Başlangıç", value: $start, range: 0...99)
                slider("Hedef", value: $target, range: 1...100)
                LabeledContent("Kapasite (kWh)") {
                    TextField("kWh", value: $capacity, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                LabeledContent("Birim fiyat (₺/kWh)") {
                    TextField("₺", value: $price, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        StatTile(title: "Enerji", value: energy.decimal(1), unit: "kWh")
                        StatTile(title: "Tahmini ücret", value: cost.decimal(), unit: "₺")
                    }
                    GridRow {
                        StatTile(title: "AC · 11 kW", value: acHours.decimal(1), unit: "sa")
                        StatTile(title: "DC · 150 kW", value: dcMinutes.decimal(), unit: "dk")
                    }
                }
                Text("Kapasite ve fiyat varsayımdır; şarj kayıpları dahil değildir. Araçta şarj başlatmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
        }
    }

    private var liveSessions: some View {
        VStack(spacing: 12) {
            SectionTitle("Bu cihazdaki son şarjlar")
            ChargeSessionList(sessions: Array(store.history.chargeSessions(lastDays: 90).prefix(5)))
        }
    }

    private var sessions: some View {
        VStack(spacing: 12) {
            SectionTitle("Son şarjlar")
            VStack(spacing: 0) {
                ForEach(SampleData.chargeSessions) { session in
                    HStack(spacing: 14) {
                        Image(systemName: session.isFast ? "bolt.fill" : "powerplug.fill")
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.18), in: .circle)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.place).font(.subheadline.weight(.medium))
                            Text(session.date.shortDateTimeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(session.energy.decimal(1)) kWh").font(.subheadline.monospacedDigit())
                            Text("\(session.cost.decimal()) ₺").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    if session.id != SampleData.chargeSessions.last?.id { Divider() }
                }
            }
            .glassCard()
        }
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(value.wrappedValue))%").font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}

#Preview {
    ChargeView().environment(GarageStore())
}
