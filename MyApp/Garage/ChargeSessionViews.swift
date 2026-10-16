import SwiftUI

/// Geçmiş kayıtlarından türetilen bir şarj oturumunun satırı.
struct ChargeSessionRow: View {
    let session: DerivedChargeSession
    let capacityKWh: Double?

    private var title: LocalizedStringKey {
        if session.isApproximate { return "Şarj · kayıt dışı" }
        switch session.isFast(capacityKWh: capacityKWh) {
        case true: return "Hızlı şarj"
        case false: return "Şarj (AC)"
        case nil: return "Şarj"
        }
    }

    private var symbol: String {
        session.isFast(capacityKWh: capacityKWh) == true ? "bolt.fill" : "powerplug.fill"
    }

    private var subtitle: String {
        if session.isApproximate {
            return "\(session.start.shortDateTimeText) ile \(session.end.shortDateTimeText) arası"
        }
        let minutes = Int((session.duration / 60).rounded())
        let duration = minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk" : "\(minutes) dk"
        return "\(session.start.shortDateTimeText) · \(duration)"
    }

    private var energyText: String {
        if let energy = session.energyKWh(capacityKWh: capacityKWh) {
            return "+\(energy.decimal(1)) kWh"
        }
        return "+%\(session.gainPercent.decimal())"
    }

    private var detailText: String {
        var text = "%\((session.startBattery * 100).decimal()) → %\((session.endBattery * 100).decimal())"
        if let power = session.averagePowerKW(capacityKWh: capacityKWh) {
            text += " · ≈ \(power.decimal()) kW"
        }
        return text
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
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
                Text(energyText).font(.subheadline.monospacedDigit())
                Text(detailText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

/// Şarj oturumları listesi; Seyahatname ve Şarj sekmesi ortak kullanır.
struct ChargeSessionList: View {
    let sessions: [DerivedChargeSession]
    let capacityKWh: Double?

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
                        ChargeSessionRow(session: session, capacityKWh: capacityKWh)
                        if session.id != sessions.last?.id { Divider() }
                    }
                }
                .glassCard()
                if let total = ChargeDeriver.totalEnergyKWh(of: sessions, capacityKWh: capacityKWh) {
                    Text("Toplam eklenen enerji ≈ \(total.decimal(1)) kWh")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                Text("Oturumlar, araç yerindeyken batarya yüzdesinin artmasından türetilir; enerji tahminidir. \"Kayıt dışı\" oturumlarda uygulama kapalıydı, bu yüzden süre ve güç bilinmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}
