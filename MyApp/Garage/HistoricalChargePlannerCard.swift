import SwiftUI

struct HistoricalChargePlannerCard: View {
    let snapshot: VehicleSnapshot
    let sessions: [DerivedChargeSession]

    private var currentBattery: Double? { snapshot.battery }

    private var averageGain: Double? {
        guard !sessions.isEmpty else { return nil }
        return sessions.map(\.gainPercent).reduce(0, +) / Double(sessions.count)
    }

    private var averageDuration: TimeInterval? {
        guard !sessions.isEmpty else { return nil }
        return sessions.map(\.duration).reduce(0, +) / Double(sessions.count)
    }

    private var preferredStartHour: Int? {
        guard !sessions.isEmpty else { return nil }
        let total = sessions.reduce(0) { partial, session in
            partial + Calendar.current.component(.hour, from: session.start)
        }
        return Int((Double(total) / Double(sessions.count)).rounded()) % 24
    }

    private var recommendation: String {
        guard let battery = currentBattery else { return "Batarya verisi bekleniyor." }
        if battery >= 0.80 {
            return "Batarya %80 üzerinde; mevcut kullanım için şarj planı gerekmiyor."
        }
        if battery <= 0.25 {
            return "Batarya düşük. Geçmiş alışkanlığına göre ilk uygun zamanda şarj planlaman önerilir."
        }
        return "Batarya seviyesi uygun. Günlük kullanım öncesi hedefi %80 olarak planlayabilirsin."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Geçmişe dayalı şarj planı", systemImage: "calendar.badge.clock")
                .font(.headline)

            Text(recommendation)
                .font(.subheadline)

            if let averageGain {
                metricRow(
                    title: "Ortalama şarj artışı",
                    value: "%\(averageGain.decimal(1))"
                )
            }

            if let averageDuration {
                metricRow(
                    title: "Ortalama şarj süresi",
                    value: durationText(averageDuration)
                )
            }

            if let preferredStartHour {
                metricRow(
                    title: "Genel şarj başlangıcı",
                    value: String(format: "%02d:00 civarı", preferredStartHour)
                )
            }

            if sessions.isEmpty {
                Text("Öneriyi kişiselleştirmek için uygulamanın birkaç şarj ölçümü kaydetmesi gerekiyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(sessions.count) yerel şarj kaydı analiz edildi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Bu yalnızca geçmişe dayalı bir öneridir; araçta otomatik şarj başlatmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func metricRow(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) dk" }
        return "\(hours) sa \(remainder) dk"
    }
}
