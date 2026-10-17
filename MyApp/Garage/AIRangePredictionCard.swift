import SwiftUI

struct AIRangePredictionCard: View {
    let snapshot: VehicleSnapshot

    @State private var explanation: String?
    @State private var failure: String?
    @State private var isThinking = false

    private var prediction: Double? {
        snapshot.realisticRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Akıllı menzil tahmini", systemImage: "location.north.line")
                .font(.headline)

            if let prediction {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(prediction.decimal())
                        .font(.system(.title, design: .rounded).weight(.semibold))
                    Text("km")
                        .foregroundStyle(.secondary)
                }

                if let shownRange = snapshot.range {
                    Text("Gösterilen menzil: \(shownRange.decimal()) km · tüketim verisine göre tahmin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch OnDeviceExplainer.availability {
                case .available:
                    Button("AI ile yorumla", systemImage: "sparkles") {
                        Task { await explain() }
                    }
                    .disabled(isThinking)

                    if isThinking {
                        ProgressView("Menzil değerlendiriliyor…")
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
            } else {
                Label("Yeterli tüketim verisi oluştuğunda tahmin gösterilecek.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Tahmin; kalan enerji ve son tüketim ortalamasından hesaplanır, resmi menzil garantisi değildir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func explain() async {
        guard let prediction else { return }

        isThinking = true
        failure = nil
        defer { isThinking = false }

        let shownRange = snapshot.range?.decimal() ?? "veri yok"
        let average = snapshot.sinceCharge.average ?? snapshot.currentTrip.average
        let prompt = """
        Hesaplanan tüketim tabanlı menzil: \(prediction.decimal()) km
        Araçta gösterilen menzil: \(shownRange) km
        Ortalama tüketim: \(average?.decimal(1) ?? "veri yok") kWh/100 km
        Batarya: \(snapshot.battery.map { ($0 * 100).decimal() } ?? "veri yok")%
        """

        do {
            explanation = try await OnDeviceExplainer.summarizeRange(prompt)
            AppLog.info(.app, "Menzil tahmini yapay zeka ile yorumlandı")
        } catch {
            AppLog.error(.app, "Menzil yorumu başarısız: \(AppLog.describe(error))")
            failure = "Yorum üretilemedi: \(error.localizedDescription)"
        }
    }
}
