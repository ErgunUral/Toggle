import SwiftUI

/// Geçmiş kayıtlarından türetilen bir şarj oturumunun satırı. Yalnızca kaydedilmiş batarya yüzdelerini
/// gösterir; enerji ya da güç tahmini yapılmaz.
struct ChargeSessionRow: View {
    let session: DerivedChargeSession

    private var title: LocalizedStringKey {
        session.isApproximate ? "Şarj · kayıt dışı" : "Şarj"
    }

    private var subtitle: String {
        if session.isApproximate {
            return "\(session.start.shortDateTimeText) ile \(session.end.shortDateTimeText) arası"
        }
        let minutes = Int((session.duration / 60).rounded())
        let duration = minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
        return "\(session.start.shortDateTimeText) · \(duration)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "powerplug.fill")
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.18), in: .circle)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+%\(session.gainPercent.decimal())").font(.subheadline.monospacedDigit())
                Text("%\((session.startBattery * 100).decimal()) → %\((session.endBattery * 100).decimal())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Şarj oturumları listesi; Seyahatname ve Şarj sekmesi ortak kullanır.
struct ChargeSessionList: View {
    let sessions: [DerivedChargeSession]

    var body: some View {
        VStack(spacing: 12) {
            if sessions.isEmpty {
                Text("Bu aralıkta şarj oturumu bulunamadı. Şarj sırasında uygulamanın açık olması ya da şarjdan önce ve sonra açılması gerekir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        ChargeSessionRow(session: session)
                        if session.id != sessions.last?.id { Divider() }
                    }
                }
                .glassCard()
                Text("Oturumlar, araç yerindeyken kaydedilen batarya yüzdesinin artmasından çıkarılır. \"Kayıt dışı\" oturumlarda uygulama kapalıydı, bu yüzden başlangıç ve bitiş zamanı kesin değildir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}
