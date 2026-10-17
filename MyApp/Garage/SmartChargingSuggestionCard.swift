import SwiftUI

struct SmartChargingSuggestionCard: View {
    let snapshot: VehicleSnapshot

    private var suggestion: SmartChargingSuggestion {
        guard let battery = snapshot.battery else {
            return SmartChargingSuggestion(
                title: "Şarj önerisi hazırlanamadı",
                detail: "Batarya yüzdesi canlı veride bulunamadı.",
                symbol: "questionmark.circle",
                tint: .secondary
            )
        }

        let percent = battery * 100
        if snapshot.isCharging == true, percent >= 80 {
            return SmartChargingSuggestion(
                title: "Günlük hedefe ulaşıldı",
                detail: "Batarya yaklaşık %\(percent.decimal()) seviyesinde. Gereksiz beklemeyi azaltmak için şarjı sonlandırmayı değerlendirin.",
                symbol: "checkmark.circle.fill",
                tint: .green
            )
        }

        if snapshot.isCharging == true {
            return SmartChargingSuggestion(
                title: "Şarj devam edebilir",
                detail: "Batarya yaklaşık %\(percent.decimal()) seviyesinde. Günlük kullanım için %80 civarı pratik bir hedef olabilir.",
                symbol: "bolt.fill",
                tint: .accentColor
            )
        }

        if percent <= 20 {
            return SmartChargingSuggestion(
                title: "Yakında şarj önerilir",
                detail: "Batarya yaklaşık %\(percent.decimal()) seviyesinde. Planlı bir kullanım öncesi şarj etmeniz önerilir.",
                symbol: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        if percent >= 80 {
            return SmartChargingSuggestion(
                title: "Şarj ihtiyacı düşük",
                detail: "Batarya yaklaşık %\(percent.decimal()) seviyesinde. Yeni bir şarj oturumu başlatmadan önce kullanım ihtiyacını değerlendirin.",
                symbol: "battery.100percent",
                tint: .green
            )
        }

        return SmartChargingSuggestion(
            title: "Şarj planı uygun",
            detail: "Mevcut seviye yaklaşık %\(percent.decimal()). Günlük kullanımınıza göre %80 civarı hedef belirleyebilirsiniz.",
            symbol: "calendar.badge.clock",
            tint: .accentColor
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.symbol)
                .font(.title3)
                .foregroundStyle(suggestion.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Akıllı şarj önerisi")
                    .font(.headline)
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                Text(suggestion.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct SmartChargingSuggestion {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
}
