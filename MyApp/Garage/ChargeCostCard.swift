import SwiftUI

/// Son 30 günün şarj oturumlarından tahmini enerji ve maliyet.
/// Oturumlar yalnızca batarya yüzdesi taşıdığından enerji, yüzde artışı × kullanılabilir kapasiteden
/// türetilir; şebekeden çekilen enerji için yaklaşık %90 şarj verimi varsayılır. Konum kaydı olmadığı için
/// ev/istasyon ayrımı yapılmaz; iki ayrı tarife girilebilir ve oturumlar kullanıcının seçtiği tarifeyle hesaplanır.
struct ChargeCostCard: View {
    let snapshot: VehicleSnapshot
    let sessions: [DerivedChargeSession]

    private static let efficiency = 0.9

    @AppStorage("chargeHomePricePerKWh") private var homePrice = 0.0
    @AppStorage("chargePublicPricePerKWh") private var publicPrice = 0.0
    @State private var usesPublicTariff = false

    private var price: Double { usesPublicTariff ? publicPrice : homePrice }

    /// Şebekeden çekilen tahmini enerji (kWh).
    private var energyKWh: Double? {
        guard let capacity = snapshot.usableCapacityKWh, !sessions.isEmpty else { return nil }
        let stored = sessions.reduce(0) { $0 + max(0, $1.gainPercent) / 100 * capacity }
        return stored / Self.efficiency
    }

    private var costPer100Km: Double? {
        guard price > 0, let average = snapshot.sinceCharge.average, average > 0 else { return nil }
        return average / Self.efficiency * price
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Şarj maliyeti (30 gün)", systemImage: "turkishlirasign.circle")
                .font(.headline)

            Picker("Tarife", selection: $usesPublicTariff) {
                Text("Ev").tag(false)
                Text("İstasyon").tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("kWh fiyatı")
                Spacer()
                TextField("0", value: usesPublicTariff ? $publicPrice : $homePrice, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("₺")
            }

            if let energyKWh {
                LabeledContent("Tahmini enerji", value: "\(energyKWh.decimal(1)) kWh")
                LabeledContent("\(sessions.count) oturum", value: price > 0 ? "\((energyKWh * price).decimal(0)) ₺" : "Fiyat gir")
            } else {
                Text("Son 30 günde kayıtlı şarj oturumu veya kapasite verisi yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let costPer100Km {
                LabeledContent("100 km maliyeti", value: "\(costPer100Km.decimal(0)) ₺")
            }

            Text("Enerji, batarya yüzdesi artışından ve yaklaşık %90 şarj verimiyle hesaplanır; fatura değeri değildir. Konum bilinmediği için tarifeyi sen seçersin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
