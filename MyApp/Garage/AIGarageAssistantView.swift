import SwiftUI
import FoundationModels

struct AIGarageAssistantView: View {
    @Environment(GarageStore.self) private var store
    @State private var question = ""
    @State private var answer: String?
    @State private var errorMessage: String?
    @State private var isThinking = false

    private var context: String {
        let snapshot = store.snapshot
        let source = store.isUsingCachedData ? "önbellek" : (snapshot.isLive ? "canlı" : "örnek")
        let battery = snapshot.battery.map { ($0 * 100).decimal() + "%" } ?? "bilinmiyor"
        let range = snapshot.range.map { $0.decimal() + " km" } ?? "bilinmiyor"
        let odometer = snapshot.odometer.map { $0.decimal() + " km" } ?? "bilinmiyor"
        let inside = snapshot.inside.map { $0.decimal() + " °C" } ?? "bilinmiyor"
        let outside = snapshot.outside.map { $0.decimal() + " °C" } ?? "bilinmiyor"
        let charging = snapshot.isCharging.map { $0 ? "şarj oluyor" : "şarj olmuyor" } ?? "bilinmiyor"
        let auxBattery = snapshot.auxBattery.map { ($0 * 100).decimal() + "%" } ?? "bilinmiyor"
        return """
        Veri kaynağı: \(source)
        Araç: \(snapshot.name), model: \(snapshot.model), versiyon: \(snapshot.edition)
        Batarya: \(battery)
        Menzil: \(range)
        Kilometre: \(odometer)
        İç sıcaklık: \(inside)
        Dış sıcaklık: \(outside)
        Şarj durumu: \(charging)
        Sürüş modu: \(snapshot.driveMode ?? "bilinmiyor")
        12 V akü: \(auxBattery)
        Son veri zamanı: \(snapshot.updatedAt?.relativeText ?? "bilinmiyor")
        """

    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AIAssistantHeader()
                AIAssistantContextCard(source: store.isUsingCachedData ? "Önbellek verisi" : (store.snapshot.isLive ? "Canlı araç verisi" : "Örnek veri"))
                AIAssistantConversation(answer: answer, errorMessage: errorMessage)
                AIAssistantComposer(
                    question: $question,
                    isThinking: isThinking,
                    isAvailable: isModelAvailable,
                    onSubmit: {
                        Task { await ask() }
                    }
                )
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("AI Garaj Asistanı")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isModelAvailable: Bool {
        if case .available = OnDeviceExplainer.availability {
            return true
        }
        return false
    }

    private func ask() async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !isThinking else { return }

        isThinking = true
        answer = nil
        errorMessage = nil
        defer { isThinking = false }

        do {
            answer = try await AIGarageAssistant.answer(question: trimmedQuestion, context: context)
            question = ""
            AppLog.info(.app, "AI Garaj Asistanı yanıt üretti")
        } catch {
            errorMessage = AIGarageAssistant.userMessage(for: error)
            AppLog.error(.app, "AI Garaj Asistanı başarısız: \(AppLog.describe(error))")
        }
    }
}

private enum AIGarageAssistant {
    static func answer(question: String, context: String) async throws -> String {
        let session = LanguageModelSession(instructions: """
            Sen Togg Garajım uygulamasının salt-okunur araç asistanısın.
            Yalnızca verilen araç verisini kullan ve Türkçe yanıt ver.
            Veride olmayan değerleri uydurma; belirsizliği açıkça belirt.
            En fazla 4 kısa cümle yaz.
            Araç kilidi, bagaj, klima veya sürüş yetkilendirme komutu çalıştırma.
            Kullanıcı komut isterse bunun bu asistanda desteklenmediğini söyle.
            """
        )
        let response = try await session.respond(to: """
            Araç verisi:
            \(context)

            Kullanıcı sorusu:
            \(question)
            """)
        return response.content
    }

    static func userMessage(for error: Error) -> String {
        let details = String(describing: error)
        if details.contains("GenerationError") || details.contains("assetsUnavailable") || details.contains("-1") {
            return "AI modeli bu simülatörde hazır değil. Apple Intelligence destekli gerçek bir cihazda veya modeli hazır olan bir ortamda tekrar deneyin."
        }
        return error.localizedDescription
    }
}

private struct AIAssistantHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Araç verilerini sor", systemImage: "sparkles")
                .font(.title2.weight(.semibold))
            Text("Batarya, menzil, sıcaklık ve şarj durumu hakkında kısa yanıtlar al.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AIAssistantContextCard: View {
    let source: String

    var body: some View {
        Label {
            Text("Yanıt kaynağı: \(source)")
        } icon: {
            Image(systemName: source == "Canlı araç verisi" ? "antenna.radiowaves.left.and.right" : "internaldrive")
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

private struct AIAssistantConversation: View {
    let answer: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let answer {
                Text(answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 16))
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Text("Örnek: “Menzilim ne kadar?” veya “Şarj durumum nasıl?”")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AIAssistantComposer: View {
    @Binding var question: String
    let isThinking: Bool
    let isAvailable: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TextField("Sorunu yaz", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

            if !isAvailable {
                Text("Bu cihazda Apple Intelligence kullanılamıyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onSubmit) {
                Label(isThinking ? "Yanıt hazırlanıyor…" : "Sor", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isThinking || !isAvailable || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
