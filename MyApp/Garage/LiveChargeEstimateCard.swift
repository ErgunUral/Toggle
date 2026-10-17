import SwiftUI

struct LiveChargeEstimateCard: View {
    let snapshot: VehicleSnapshot

    @State private var targetPercent = 80.0
    @State private var chargingPower = 11.0

    private var currentPercent: Double? {
        snapshot.battery.map { $0 * 100 }
    }

    private var energyToTarget: Double? {
        guard let battery = snapshot.battery,
              let capacity = snapshot.usableCapacityKWh,
              targetPercent > battery * 100 else {
            return 0
        }
        return (targetPercent / 100 - battery) * capacity
    }

    private var estimateHours: Double? {
        guard let energyToTarget, energyToTarget > 0, chargingPower > 0 else {
            return 0
        }
        return energyToTarget / chargingPower / 0.9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Şarj tahmini", systemImage: "bolt.badge.clock")
                .font(.headline)

            Picker("AC güç profili", selection: $chargingPower) {
                Text("3,7 kW").tag(3.7)
                Text("7,4 kW").tag(7.4)
                Text("11 kW").tag(11.0)
                Text("22 kW").tag(22.0)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Hedef")
                    Spacer()
                    Text("\(targetPercent.decimal())%")
                        .fontWeight(.semibold)
                }
                Slider(value: $targetPercent, in: 50...100, step: 1)
            }

            if let currentPercent {
                LabeledContent("Mevcut seviye", value: "\(currentPercent.decimal())%")
            }

            LabeledContent(
                "Gerekli enerji",
                value: energyToTarget.map { "\($0.decimal(1)) kWh" } ?? "Hesaplanamıyor"
            )

            if let estimateHours, estimateHours > 0 {
                LabeledContent("Tahmini süre", value: estimateHours.durationText)
                if snapshot.isCharging == true {
                    LabeledContent(
                        "Tahmini bitiş",
                        value: Date.now.addingTimeInterval(estimateHours * 3600)
                            .formatted(date: .omitted, time: .shortened)
                    )
                }
            } else {
                Text("Hedef zaten karşılanmış veya yeterli batarya verisi yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Anlık şarj kW değeri API’den gelmediği için süre seçilen AC güç profili ve yaklaşık %90 verimle hesaplanır. Araçta şarj başlatmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private extension Double {
    var durationText: String {
        let hours = Int(self)
        let minutes = Int((self - Double(hours)) * 60)
        if hours == 0 {
            return "\(minutes) dk"
        }
        return "\(hours) sa \(minutes) dk"
    }
}
