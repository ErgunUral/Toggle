import SwiftUI

struct VehicleHealthInsightsCard: View {
    let snapshot: VehicleSnapshot

    @State private var explanation: String?
    @State private var failure: String?
    @State private var isThinking = false

    private var observations: [String] {
        var items: [String] = []

        if let brakeWarning = snapshot.brakeWarning, brakeWarning {
            items.append("Fren uyarısı etkin")
        }
        if let engineWarning = snapshot.engineWarning, engineWarning {
            items.append("Motor/aktarma uyarısı etkin")
        }
        if AuxBattery.isLow(snapshot.auxBattery) {
            items.append("12 V akü seviyesi düşük")
        }
        if let battery = snapshot.battery, battery <= 0.20 {
            items.append("Yüksek öncelik: çekiş bataryası %\( (battery * 100).decimal() )")
        }
        if let range = snapshot.range, let realisticRange = snapshot.realisticRange {
            let difference = abs(range - realisticRange)
            if difference > max(40, range * 0.15) {
                items.append("Gösterilen menzil ile tüketim tabanlı tahmin arasında fark var")
            }
        }
        let tireValues = [
            snapshot.tires.frontLeft,
            snapshot.tires.frontRight,
            snapshot.tires.rearLeft,
            snapshot.tires.rearRight
        ].compactMap { $0 }
        if let minimum = tireValues.min(), minimum < 31 {
            items.append("Lastiklerden en az biri düşük basınçta görünüyor")
        }
        if items.isEmpty {
            items.append("Belirgin bir anomali tespit edilmedi")
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Araç sağlık özeti", systemImage: "heart.text.square")
                .font(.headline)

            ForEach(observations, id: \.self) { observation in
                Label(observation, systemImage: observation.contains("tespit edilmedi") ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(observation.contains("tespit edilmedi") ? Color.secondary : Color.orange)
            }

            switch OnDeviceExplainer.availability {
            case .available:
                Button("AI ile değerlendir", systemImage: "sparkles") {
                    Task { await evaluate() }
                }
                .disabled(isThinking)

                if isThinking {
                    ProgressView("Durum değerlendiriliyor…")
                }

                if let explanation {
                    Text(explanation)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                if let failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .unavailable(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Bu bölüm tanı koymaz; yalnızca mevcut telemetrideki dikkat noktalarını özetler.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func evaluate() async {
        isThinking = true
        failure = nil
        defer { isThinking = false }

        do {
            explanation = try await OnDeviceExplainer.summarizeHealth(
                AIHealthPrompt.make(snapshot: snapshot, observations: observations)
            )
            AppLog.info(.app, "Araç sağlık özeti yapay zeka ile değerlendirildi")
        } catch {
            AppLog.error(.app, "Araç sağlık özeti başarısız: \(AppLog.describe(error))")
            failure = "Değerlendirme üretilemedi: \(error.localizedDescription)"
        }
    }
}

private enum AIHealthPrompt {
    static func make(snapshot: VehicleSnapshot, observations: [String]) -> String {
        let battery = snapshot.battery.map { "\(($0 * 100).decimal())%" } ?? "veri yok"
        let range = snapshot.range.map { "\($0.decimal()) km" } ?? "veri yok"
        let auxBattery = snapshot.auxBattery.map { "\(($0 * 100).decimal())%" } ?? "veri yok"
        let tireValues = [
            snapshot.tires.frontLeft,
            snapshot.tires.frontRight,
            snapshot.tires.rearLeft,
            snapshot.tires.rearRight
        ].compactMap { $0 }
        let tires = tireValues.map { $0.decimal(1) }.joined(separator: ", ")

        return """
        Araç durumu:
        çekiş bataryası=\(battery), menzil=\(range), 12 V akü=\(auxBattery)
        lastik basınçları=\(tires), şarj=\(snapshot.isCharging == true ? "devam ediyor" : "devam etmiyor")
        fren uyarısı=\(snapshot.brakeWarning == true ? "var" : "yok"), motor uyarısı=\(snapshot.engineWarning == true ? "var" : "yok")

        Ön değerlendirmeler:
        \(observations.joined(separator: "\n"))
        """
    }
}
