import Foundation

/// Geçmiş noktalarından türetilen bir gezi. Konum içermez; sınırlar kayıt sıklığına bağlı olduğundan yaklaşıktır.
/// Yalnızca ölçülmüş değerleri taşır (kilometre sayacı, batarya yüzdesi, dış sıcaklık); enerji ya da
/// tüketim gibi tahmini değerler içermez.
nonisolated struct DerivedTrip: Identifiable, Sendable {
    let start: Date
    let end: Date
    let distanceKm: Double
    /// 0...1
    let startBattery: Double?
    let endBattery: Double?
    let averageOutsideTemp: Double?

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Gezi boyunca kaydedilen batarya yüzdesi farkı; gezi sırasında şarj olduysa ya da veri yoksa nil.
    var batteryUsedPercent: Double? {
        guard let startBattery, let endBattery, startBattery >= endBattery else { return nil }
        return (startBattery - endBattery) * 100
    }
}

nonisolated enum TripDeriver {
    /// Ardışık iki kayıt arası bundan uzunsa aradaki kilometre bir geziye yazılmaz.
    static let maximumGap: TimeInterval = 30 * 60
    /// Bundan kısa kilometre farkı gezi sayılmaz (sensör gürültüsü).
    static let minimumTripDistanceKm = 0.5

    /// Kilometre sayacı artan ardışık kayıtları bir gezide toplar. Sayaç değişmeyen, sayacı olmayan
    /// ya da `maximumGap`'ten uzun aralıklar geziyi bitirir.
    static func trips(from points: [HistoryPoint]) -> [DerivedTrip] {
        let sorted = points.sorted { $0.date < $1.date }
        var result: [DerivedTrip] = []
        var run: [(HistoryPoint, HistoryPoint)] = []

        func flush() {
            defer { run.removeAll() }
            guard let first = run.first, let last = run.last else { return }
            let distance = run.reduce(0) { $0 + (($1.1.odometerKm ?? 0) - ($1.0.odometerKm ?? 0)) }
            guard distance >= minimumTripDistanceKm else { return }
            let temps = run.flatMap { [$0.0.outsideTemp, $0.1.outsideTemp] }.compactMap { $0 }
            result.append(DerivedTrip(
                start: first.0.date,
                end: last.1.date,
                distanceKm: distance,
                startBattery: first.0.battery,
                endBattery: last.1.battery,
                averageOutsideTemp: temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
            ))
        }

        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            guard let a = earlier.odometerKm, let b = later.odometerKm else { flush(); continue }
            let delta = b - a
            let gap = later.date.timeIntervalSince(earlier.date)
            // 1500 km üzeri sıçrama veri hatası sayılır (dailyDistances ile aynı).
            if delta > 0, delta < 1500, gap > 0, gap <= maximumGap {
                run.append((earlier, later))
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}
