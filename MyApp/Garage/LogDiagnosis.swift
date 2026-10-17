import SwiftUI
import FoundationModels

// MARK: - Kural tabanlı özet

struct DiagnosisFinding: Identifiable {
    let id = UUID()
    let text: String
}

struct DiagnosisSummary {
    var verdict: String
    var findings: [DiagnosisFinding]
}

/// Günlükten, yapay zeka olmadan çıkarılabilen özeti üretir.
enum LogAnalyzer {
    static func summarize(_ entries: [LogEntry]) -> DiagnosisSummary {
        let errors = entries.filter { $0.level == .error }
        let warnings = entries.filter { $0.level == .warning }
        var findings = [DiagnosisFinding(text: "\(entries.count) kayıt: \(errors.count) hata, \(warnings.count) uyarı.")]

        let lastRefresh = entries.last {
            $0.message.hasPrefix("Canlı yenileme tamamlandı") || $0.message.hasPrefix("Canlı yenileme başarısız")
        }
        let refreshSucceeded = lastRefresh?.message.hasPrefix("Canlı yenileme tamamlandı") == true
        if let lastRefresh {
            findings.append(DiagnosisFinding(text: "Son yenileme: \(lastRefresh.message)"))
        } else {
            findings.append(DiagnosisFinding(text: "Henüz canlı yenileme kaydı yok; örnek modda olabilirsin."))
        }

        // Her adres için son HTTP durumu.
        var lastStatus: [(String, String)] = []
        for entry in entries where entry.message.contains(" → HTTP") {
            let parts = entry.message.components(separatedBy: " → ")
            guard parts.count == 2 else { continue }
            lastStatus.removeAll { $0.0 == parts[0] }
            lastStatus.append((parts[0], parts[1]))
        }
        for (request, status) in lastStatus {
            findings.append(DiagnosisFinding(text: "\(request) → \(status)"))
        }

        if let fields = entries.last(where: { $0.message.hasPrefix("Alan özeti") }) {
            findings.append(DiagnosisFinding(text: fields.message))
        }
        for entry in errors.suffix(3) {
            findings.append(DiagnosisFinding(text: "Hata (\(entry.category.rawValue)): \(entry.message)"))
        }

        let verdict: String
        if !errors.isEmpty {
            verdict = "Hata kayıtları var; aşağıdaki son hatalara bak."
        } else if refreshSucceeded {
            verdict = "Canlı bağlantı sağlıklı görünüyor."
        } else {
            verdict = "Yorum için yeterli kayıt yok."
        }
        return DiagnosisSummary(verdict: verdict, findings: findings)
    }

    /// Cihaz üstü modele verilecek, kısaltılmış günlük metni. Hata ve adım kayıtlarını önceler.
    static func promptText(_ entries: [LogEntry], limit: Int = 3500) -> String {
        let text = entries
            .filter { $0.level != .debug }
            .suffix(40)
            .map(\.line)
            .joined(separator: "\n")
        return String(text.suffix(limit))
    }
}

// MARK: - Cihaz üstü yapay zeka

/// Apple'ın cihaz üstü dil modeli. Günlük cihazdan çıkmaz.
enum OnDeviceExplainer {
    enum Availability {
        case available
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Bu cihaz Apple Intelligence'ı desteklemiyor.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence ayarlardan açık değil.")
        case .unavailable(.modelNotReady):
            return .unavailable("Dil modeli henüz hazır değil; biraz sonra tekrar dene.")
        case .unavailable:
            return .unavailable("Dil modeli şu an kullanılamıyor.")
        }
    }

    static func explain(_ logText: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Sen bir araç uygulamasının tanılama yardımcısısın. Verilen günlük satırlarına bakarak \
            hangi adımların başarılı, hangisinin başarısız olduğunu ve olası nedenini sade Türkçe ile \
            en fazla 5 cümlede açıkla. Günlükte olmayan bir şeyi uydurma; emin değilsen bunu söyle. \
            Parola, belirteç ya da kimlik bilgisi isteme.
            """)
        let response = try await session.respond(to: "Günlük:\n\(logText)")
        return response.content
    }

    static func summarizeAnalytics(_ analyticsText: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Sen Togg araç analiz yardımcısısın. Verilen yolculuk ve şarj ölçümlerini sade Türkçe ile özetle.
            En fazla 4 cümle yaz: önce belirgin eğilimi söyle, sonra yalnızca veriden desteklenen bir veya iki öneri ver.
            Verilmeyen değerleri uydurma. Güvenlik, bakım veya menzil konusunda kesin hüküm verme.
            """)
        let response = try await session.respond(to: "Araç analiz verileri:\n\(analyticsText)")
        return response.content
    }

    static func summarizeHealth(_ healthText: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Sen araç telemetrisi açıklayan bir yardımcı rolündesin. Verilen ölçümleri ve ön değerlendirmeleri sade Türkçe ile açıkla.
            En fazla 4 cümle yaz. Öncelik sırasını belirt; kesin teşhis, güvenlik garantisi veya bakım kararı verme.
            Sadece verilen verilere dayan ve belirsizliği açıkça söyle.
            """)
        let response = try await session.respond(to: "Araç sağlık verileri:\n\(healthText)")
        return response.content
    }

    static func summarizeRange(_ rangeText: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Sen elektrikli araç menzil verilerini açıklayan bir yardımcısın. Hesaplanan tahmin ile araç göstergesini sade Türkçe ile karşılaştır.
            En fazla 3 cümle yaz. Tahmini kesin gerçek gibi sunma; yalnızca verilen değerlere dayan ve belirsizliği belirt.
            """)
        let response = try await session.respond(to: "Menzil verileri:\n\(rangeText)")
        return response.content
    }
}

// MARK: - Ekran

struct LogDiagnosisView: View {
    let entries: [LogEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var summary: DiagnosisSummary
    @State private var explanation: String?
    @State private var failure: String?
    @State private var isThinking = false

    init(entries: [LogEntry]) {
        self.entries = entries
        _summary = State(initialValue: LogAnalyzer.summarize(entries))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Özet") {
                    Text(summary.verdict).font(.headline)
                    ForEach(summary.findings) { finding in
                        Text(finding.text).font(.caption.monospaced())
                    }
                }
                aiSection
            }
            .navigationTitle("Günlüğü açıkla")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var aiSection: some View {
        Section {
            switch OnDeviceExplainer.availability {
            case .available:
                Button("Yapay zeka ile açıkla", systemImage: "sparkles") {
                    Task { await explain() }
                }
                .disabled(isThinking)
                if isThinking { ProgressView() }
                if let explanation { Text(explanation) }
                if let failure { Text(failure).foregroundStyle(.orange) }
            case .unavailable(let reason):
                Text(reason).foregroundStyle(.secondary)
            }
        } header: {
            Text("Yapay zeka")
        } footer: {
            Text("Cihaz üstünde çalışır; günlük cihazdan çıkmaz. Yanıtı yukarıdaki özetle karşılaştır.")
        }
    }

    private func explain() async {
        isThinking = true
        failure = nil
        defer { isThinking = false }
        do {
            explanation = try await OnDeviceExplainer.explain(LogAnalyzer.promptText(entries))
            AppLog.info(.app, "Günlük yapay zeka ile açıklandı")
        } catch {
            AppLog.error(.app, "Yapay zeka açıklaması başarısız: \(AppLog.describe(error))")
            failure = "Açıklama üretilemedi: \(error.localizedDescription)"
        }
    }
}
