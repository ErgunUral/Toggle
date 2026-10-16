import Foundation

/// Geçmiş noktalarından türetilen bir şarj oturumu. Konum içermez.
/// Yalnızca kaydedilmiş batarya yüzdelerini taşır; enerji (kWh) ya da güç gibi tahmini değerler içermez.
/// `isApproximate`: uygulama şarj sırasında kapalıydı; yalnızca önceki ve sonraki kayıt arasındaki
/// batarya artışı biliniyor, başlangıç/bitiş zamanı kesin değil.
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
}
