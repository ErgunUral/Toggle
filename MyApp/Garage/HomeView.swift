import SwiftUI

struct HomeView: View {
    @Environment(GarageStore.self) private var store
    @State private var showNotifications = false

    private var subtitle: String {
        let kind = store.snapshot.isLive ? "Canlı veri" : "Örnek veri"
        guard let updatedAt = store.snapshot.updatedAt else { return "\(kind) · Veri zamanı bilinmiyor" }
        return "\(kind) · \(updatedAt.relativeText)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let message = store.message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HeroSection()
                    QuickActions()
                    HStack(alignment: .top, spacing: 14) {
                        MeterCard(
                            title: "12 V akü",
                            symbol: "minus.plus.batteryblock",
                            value: store.snapshot.auxBattery ?? 0,
                            caption: store.snapshot.auxBattery.map { "\(($0 * 100).decimal())% dolu" } ?? "Veri yok",
                            isSample: false
                        )
                        MeterCard(
                            title: "İnternet",
                            symbol: "antenna.radiowaves.left.and.right",
                            value: store.snapshot.internetUsedGB / store.snapshot.internetQuotaGB,
                            caption: "\(store.snapshot.internetUsedGB.decimal(1)) / \(store.snapshot.internetQuotaGB.decimal()) GB",
                            isSample: store.snapshot.isLive
                        )
                    }
                    VehicleStatusCard()
                    TripSection()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .navigationTitle(store.snapshot.name)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Bildirimler", systemImage: "bell") { showNotifications = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Yenile", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isRefreshing)
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showNotifications) {
                NavigationStack {
                    NotificationsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Kapat") { showNotifications = false }
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Hero

private struct HeroSection: View {
    @Environment(GarageStore.self) private var store
    @State private var frame = 0
    @State private var dragStartFrame: Int?
    @State private var showsSpin = false
    @State private var autoSpin = false

    private var color: VehicleColor { store.color }

    private var imageName: String {
        showsSpin && color.hasSpin ? color.spinFrame(frame) : color.imageName
    }

    var body: some View {
        let snapshot = store.snapshot
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(snapshot.battery.map { ($0 * 100).decimal() } ?? "—")
                            .font(.system(size: 68, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("%").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Label("\(snapshot.range.decimal()) km menzil", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let realistic = snapshot.realisticRange {
                        Text("Gerçekçi ≈ \(realistic.decimal()) km · son tüketime göre")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Dış \(snapshot.outside.decimal())°", systemImage: "thermometer.medium")
                    Label("Kabin \(snapshot.inside.decimal())°", systemImage: "car.side")
                        .accessibilityLabel("Kabin sıcaklığı \(snapshot.inside.decimal()) derece")
                }
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }

            VehicleImageView(name: imageName)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .gesture(spinGesture)
                .accessibilityElement()
                .accessibilityLabel("Togg T10X, \(color.title)")

            if color.hasSpin {
                HStack {
                    Label("Döndürmek için sürükle", systemImage: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(autoSpin ? "Durdur" : "360°", systemImage: autoSpin ? "pause.fill" : "rotate.3d") {
                        autoSpin.toggle()
                        if autoSpin { showsSpin = true }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            colorPicker
        }
        .task(id: autoSpin) {
            while autoSpin {
                try? await Task.sleep(for: .milliseconds(110))
                if Task.isCancelled { break }
                frame = (frame + 1) % VehicleColor.spinFrameCount
            }
        }
        .onChange(of: store.color) {
            showsSpin = false
            autoSpin = false
            frame = 0
        }
    }

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard color.hasSpin else { return }
                autoSpin = false
                showsSpin = true
                let start = dragStartFrame ?? frame
                dragStartFrame = start
                // Her 16 pt sürükleme bir kare ilerletir.
                let steps = Int((value.translation.width / 16).rounded(.towardZero))
                let count = VehicleColor.spinFrameCount
                frame = ((start - steps) % count + count) % count
            }
            .onEnded { _ in dragStartFrame = nil }
    }

    private var colorPicker: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(VehicleColor.allCases) { option in
                        Button { store.select(option) } label: {
                            Circle()
                                .fill(option.swatch)
                                .frame(width: 28, height: 28)
                                .overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                                .padding(4)
                                .overlay {
                                    if option == store.color {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(option == store.color ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            Text(color.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hızlı işlemler

private struct QuickActions: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        // Canlı modda araç durumu okunmadığı için bu kutucuklar devre dışıdır.
        let isLive = snapshot.isLive
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                tile(
                    "Kapılar",
                    detail: isLive ? "Salt okunur" : (snapshot.doorsLocked ? "Kilitli" : "Açık"),
                    symbol: snapshot.doorsLocked || isLive ? "lock.fill" : "lock.open.fill",
                    isActive: snapshot.doorsLocked && !isLive
                ) { store.toggleLock() }
                tile(
                    "Klima",
                    detail: isLive ? "Salt okunur" : (snapshot.climateOn ? "\(snapshot.targetTemperature)°C" : "Kapalı"),
                    symbol: "fan.fill",
                    isActive: snapshot.climateOn && !isLive
                ) { store.toggleClimate() }
                tile(
                    "Bagaj",
                    detail: isLive ? "Salt okunur" : (snapshot.trunkOpen ? "Açık" : "Kapalı"),
                    symbol: "car.rear.fill",
                    isActive: snapshot.trunkOpen && !isLive
                ) { store.toggleTrunk() }
            }
            .disabled(isLive)
        }
        .sensoryFeedback(.impact, trigger: snapshot.doorsLocked)
        .sensoryFeedback(.impact, trigger: snapshot.trunkOpen)
        .sensoryFeedback(.impact, trigger: snapshot.climateOn)
    }

    private func tile(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                VStack(spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isActive ? .regular.tint(Color.accentColor.opacity(0.25)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 24)
        )
    }
}

// MARK: - Kartlar

private struct MeterCard: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: Double
    let caption: String
    /// Canlı modda, canlı kaynağı olmayan kartları "Örnek" diye işaretler.
    let isSample: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            MeterBar(value: value)
            HStack {
                Text(caption).font(.callout.weight(.medium).monospacedDigit())
                if isSample { SampleTag() }
            }
        }
        .glassCard()
    }
}

struct SampleTag: View {
    var body: some View {
        Text("Örnek")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.18), in: .capsule)
            .foregroundStyle(.secondary)
    }
}

private struct VehicleStatusCard: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        VStack(spacing: 12) {
            SectionTitle("Araç durumu")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    StatTile(title: "Kilometre", value: snapshot.odometer.decimal(), unit: "km")
                    StatTile(title: "Sürüş modu", value: snapshot.driveMode ?? "—")
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        StatTile(title: "Sol ön lastik", value: snapshot.tires.frontLeft.decimal(), unit: "PSI")
                        StatTile(title: "Sağ ön lastik", value: snapshot.tires.frontRight.decimal(), unit: "PSI")
                    }
                    GridRow {
                        StatTile(title: "Sol arka lastik", value: snapshot.tires.rearLeft.decimal(), unit: "PSI")
                        StatTile(title: "Sağ arka lastik", value: snapshot.tires.rearRight.decimal(), unit: "PSI")
                    }
                }
            }
            .glassCard()
        }
    }
}

private struct TripSection: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            SectionTitle(store.snapshot.isLive && !store.snapshot.tripsAreLive ? "Sürüş · örnek veri" : "Sürüş")
            NavigationLink {
                JourneyView()
            } label: {
                TripCard(title: "Güncel sürüş", stats: store.snapshot.currentTrip)
            }
            .buttonStyle(.plain)
            NavigationLink {
                JourneyView()
            } label: {
                TripCard(title: "Son şarjdan itibaren", stats: store.snapshot.sinceCharge)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TripCard: View {
    let title: LocalizedStringKey
    let stats: TripStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    StatTile(title: "Mesafe", value: stats.distance.decimal(1), unit: "km")
                    StatTile(title: "Ort. tüketim", value: stats.average.decimal(1), unit: "kWh/100 km")
                }
                GridRow {
                    StatTile(title: "Tahmini enerji", value: stats.energy.decimal(1), unit: "kWh")
                    StatTile(title: "Batarya tüketimi", value: stats.batteryPercent.decimal(1), unit: "%")
                }
            }
            Text(stats.note).font(.caption).foregroundStyle(.secondary)
        }
        .glassCard()
    }
}

#Preview {
    HomeView().environment(GarageStore())
}
