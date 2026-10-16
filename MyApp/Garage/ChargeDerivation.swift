import Foundation

/// Geçmiş noktalarından türetilen bir şarj oturumu. Konum içermez.
/// `isApproximate`: uygulama şarj sırasında kapalıydı; yalnızca önceki ve sonraki kayıt arasındaki
/// batarya artışı biliniyor, başlangıç/bitiş zamanı ve güç bilinmiyor.
nonisolated struct DerivedChargeSession: Identifiable, Sendable {
    let start: Date
    let end: Date
    /// 0...1
    let startBattery: Double
    let endBattery: Double
    let isApproximate: Bool

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var gainPercent: Double { (endBattery - startBattery) * 100 }

    func energyKWh(capacityKWh: Double?) -> Double? {
        guard let capacityKWh, capacityKWh > 0 else { return nil }
        return (endBattery - startBattery) * capacityKWh
    }

    /// Ortalama güç (kW). Süre bilinmiyorsa ya da çok kısaysa nil; batarya yüzdesi tam sayı
    /// olduğundan 10 dakikadan kısa oturumlarda sonuç çok kaba olurdu.
    func averagePowerKW(capacityKWh: Double?) -> Double? {
        guard !isApproximate, duration >= ChargeDeriver.minimumDurationForPower,
              let energy = energyKWh(capacityKWh: capacityKWh) else { return nil }
        return energy / (duration / 3600)
    }

    /// Ortalama güce göre DC (hızlı) şarj; güç bilinmiyorsa nil.
    func isFast(capacityKWh: Double?) -> Bool? {
        averagePowerKW(capacityKWh: capacityKWh).map { $0 >= ChargeDeriver.fastChargePowerKW }
    }
}

nonisolated enum ChargeDeriver {
    /// Ardışık iki kayıt arası bundan uzunsa oturum kesintisiz kaydedilmiş sayılmaz.
    static let maximumGap: TimeInterval = 60 * 60
    /// Kesintisiz olmayan artış, aradaki süre bundan uzunsa şarj sayılmaz.
    static let maximumApproximateGap: TimeInterval = 24 * 3600
    /// Tam sayı yüzde dalgalanmasını (+1) şarj saymamak için en az bu artış (0...1).
    static let minimumGain = 0.02
    static let minimumApproximateGain = 0.03
    /// Şarj sırasında araç yerinde durur; bundan fazla kilometre artışı sürüş sayılır.
    static let maximumDrivenKm = 0.5
    static let minimumDurationForPower: TimeInterval = 10 * 60
    static let fastChargePowerKW = 30.0

    /// Araç yerindeyken batarya artan ardışık kayıtları (ya da şarj bayrağı olanları) bir oturumda toplar.
    static func sessions(from points: [HistoryPoint]) -> [DerivedChargeSession] {
        let sorted = points.sorted { $0.date < $1.date }
        var result: [DerivedChargeSession] = []
        var run: [(HistoryPoint, HistoryPoint)] = []

        func flush() {
            defer { run.removeAll() }
            guard let first = run.first, let last = run.last,
                  let start = first.0.battery, let end = last.1.battery,
                  end - start >= minimumGain else { return }
            result.append(DerivedChargeSession(
                start: first.0.date,
                end: last.1.date,
                startBattery: start,
                endBattery: end,
                isApproximate: false
            ))
        }

        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            guard let before = earlier.battery, let after = later.battery else { flush(); continue }
            let gap = later.date.timeIntervalSince(earlier.date)
            var driven = 0.0
            if let a = earlier.odometerKm, let b = later.odometerKm { driven = b - a }
            guard gap > 0, driven < maximumDrivenKm else { flush(); continue }

            let gain = after - before
            let flaggedCharging = earlier.isCharging == true || later.isCharging == true
            if gap <= maximumGap, gain >= 0, gain > 0 || flaggedCharging {
                run.append((earlier, later))
            } else {
                flush()
                if gap > maximumGap, gap <= maximumApproximateGap, gain >= minimumApproximateGain {
                    result.append(DerivedChargeSession(
                        start: earlier.date,
                        end: later.date,
                        startBattery: before,
                        endBattery: after,
                        isApproximate: true
                    ))
                }
            }
        }
        flush()
        return result
    }

    /// Toplam eklenen enerji (kWh); kapasite bilinmiyorsa nil.
    static func totalEnergyKWh(of sessions: [DerivedChargeSession], capacityKWh: Double?) -> Double? {
        guard capacityKWh != nil, !sessions.isEmpty else { return nil }
        return sessions.reduce(0) { $0 + ($1.energyKWh(capacityKWh: capacityKWh) ?? 0) }
    }
}
