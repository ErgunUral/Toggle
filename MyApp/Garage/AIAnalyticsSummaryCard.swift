import SwiftUI

struct AIAnalyticsSummaryCard: View {
    let blocks: [ServerInsightBlock]
    let records: [ServerRecord]
    let isCharge: Bool

    @State private var summary: String?
    @State private var failure: String?
    @State private var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIAnalyticsSummaryHeader()

            switch OnDeviceExplainer.availability {
            case .available:
                Button("AI ile özetle", systemImage: "sparkles") {
                    Task { await generateSummary() }
                }
                .disabled(isThinking)

                if isThinking {
                    ProgressView("Veriler değerlendiriliyor…")
                }

                if let summary {
                    Text(summary)
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Özet yalnızca bu ekrandaki ölçümlerle oluşturulur ve cihaz üzerinde işlenir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func generateSummary() async {
        isThinking = true
        failure = nil
        defer { isThinking = false }

        do {
            summary = try await OnDeviceExplainer.summarizeAnalytics(
                AIAnalyticsPrompt.make(blocks: blocks, records: records, isCharge: isCharge)
            )
            AppLog.info(.app, "Analiz yapay zeka ile özetlendi")
        } catch {
            AppLog.error(.app, "Analiz özeti başarısız: \(AppLog.describe(error))")
            failure = "Özet üretilemedi: \(error.localizedDescription)"
        }
    }
}

private struct AIAnalyticsSummaryHeader: View {
    var body: some View {
        Label("Akıllı analiz özeti", systemImage: "sparkles")
            .font(.headline)
    }
}

private enum AIAnalyticsPrompt {
    static func make(
        blocks: [ServerInsightBlock],
        records: [ServerRecord],
        isCharge: Bool
    ) -> String {
        let blockText = blocks.map { block in
            let metrics = block.metrics
            return [
                block.title,
                "mesafe=\(metrics.distanceKm.decimal(1)) km",
                "tüketim=\(metrics.consumedKWh.decimal(1)) kWh",
                "ortalama=\(metrics.averageKWhPer100Km.decimal(1)) kWh/100 km",
                "yolculuk=\(metrics.journeyCount.decimal())",
                "sürüş=\(metrics.drivingHours.decimal(1)) saat",
                "ekonomi=\(metrics.economyScore.decimal())/100",
                "şarj=\(metrics.chargeCount.decimal())",
                "eklenen enerji=\(metrics.addedKWh.decimal(1)) kWh"
            ].joined(separator: ", ")
        }.joined(separator: "\n")

        let recordText = records.prefix(20).map { record in
            if isCharge {
                return "şarj: başlangıç %\(record.socStartPercent.decimal()), bitiş %\(record.socEndPercent.decimal()), eklenen \(record.addedKWh.decimal(1)) kWh, süre \(record.durationMinutes.decimal()) dk"
            }
            return "yolculuk: \(record.distanceKm.decimal(1)) km, tüketim \(record.consumedKWh.decimal(1)) kWh, süre \(record.durationMinutes.decimal()) dk"
        }.joined(separator: "\n")

        return """
        Dönem özetleri:
        \(blockText.isEmpty ? "Veri yok" : blockText)

        Son kayıtlar:
        \(recordText.isEmpty ? "Veri yok" : recordText)
        """
    }
}
