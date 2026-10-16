import SwiftUI

struct ClimateView: View {
    @Environment(GarageStore.self) private var store
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorText: String?
    @State private var commandStatus: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    dial
                    Button(
                        store.snapshot.climateOn ? "Klimayı kapat" : "Klimayı başlat",
                        systemImage: "power"
                    ) {
                        if store.snapshot.isLive {
                            Task { await toggleLiveClimate() }
                        } else {
                            store.toggleClimate()
                        }
                    }
                    .disabled(isLoading || isSending)
                    .buttonStyle(.glassProminent)
                        .controlSize(.large)

                    if !store.snapshot.isLive {
                        Picker("Mod", selection: $store.snapshot.climateMode) {
                            ForEach(ClimateMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 0) {
                            option("Ön cam buz çözme", symbol: "windshield.front.and.heat.waves", isOn: $store.snapshot.defrost)
                            Divider()
                            option("Direksiyon ısıtma", symbol: "steeringwheel.and.heat.waves", isOn: $store.snapshot.steeringHeat)
                            Divider()
                            option("Sürücü koltuğu ısıtma", symbol: "heat.waves", isOn: $store.snapshot.driverSeatHeat)
                            Divider()
                            option("Yolcu koltuğu ısıtma", symbol: "heat.waves", isOn: $store.snapshot.passengerSeatHeat)
                        }
                        .glassCard()
                    }

                    if isLoading || isSending {
                        ProgressView(isSending ? "Komut gönderiliyor…" : "Klima durumu okunuyor…")
                            .frame(maxWidth: .infinity)
                    }

                    if let commandStatus {
                        Label(commandStatus, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text(store.snapshot.isLive
                         ? "Klima durumu ve komutları Togg servisinden okunur."
                         : "Örnek veri üzerinde çalışır; araca komut göndermez.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .refreshable {
                if store.snapshot.isLive {
                    await loadLiveClimate()
                }
            }
            .task(id: "\(store.selectedVIN ?? "")-\(store.snapshot.isLive)") {
                if store.snapshot.isLive {
                    await loadLiveClimate()
                }
            }
            .navigationTitle("Klima")
            .navigationSubtitle("Kabin \(store.snapshot.inside.decimal())°C")
        }
    }

    private var dial: some View {
        let snapshot = store.snapshot
        let progress = Double(snapshot.targetTemperature - 16) / 14
        return VStack(spacing: 20) {
            ZStack {
                RingGauge(value: progress, lineWidth: 16)
                    .opacity(snapshot.climateOn ? 1 : 0.4)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(snapshot.targetTemperature)")
                            .font(.system(size: 84, weight: .light, design: .rounded))
                            .contentTransition(.numericText())
                        Text("°C").font(.title2).foregroundStyle(.secondary)
                    }
                    Text(snapshot.climateOn ? "Hedef sıcaklık" : "Klima kapalı")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250)
            .animation(.smooth, value: snapshot.targetTemperature)

            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 28) {
                    Button { store.adjustTemperature(by: -1) } label: {
                        Image(systemName: "minus").font(.title2.weight(.semibold)).frame(width: 52, height: 52)
                    }
                    .accessibilityLabel("Sıcaklığı azalt")
                    Button { store.adjustTemperature(by: 1) } label: {
                        Image(systemName: "plus").font(.title2.weight(.semibold)).frame(width: 52, height: 52)
                    }
                    .accessibilityLabel("Sıcaklığı artır")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            .sensoryFeedback(.selection, trigger: snapshot.targetTemperature)
        }
        .padding(.top, 8)
    }

    private func loadLiveClimate() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let climate = try await store.climateState()
            store.snapshot.climateOn = climate.active
            if let temperature = climate.temperature {
                store.snapshot.targetTemperature = min(
                    GarageStore.climateTemperatureRange.upperBound,
                    max(GarageStore.climateTemperatureRange.lowerBound, Int(temperature.rounded()))
                )
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleLiveClimate() async {
        guard !isSending else { return }
        isSending = true
        errorText = nil
        commandStatus = nil
        defer { isSending = false }

        do {
            let result = try await store.sendClimateCommand(
                enabled: !store.snapshot.climateOn,
                temperature: Double(store.snapshot.targetTemperature)
            )
            commandStatus = result.status.isEmpty ? "Komut tamamlandı." : "Komut: (result.status)"
            await loadLiveClimate()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func option(_ title: LocalizedStringKey, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    ClimateView().environment(GarageStore())
}
