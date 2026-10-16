import Foundation

/// Geçmiş noktalarından türetilen bir gezi. Konum içermez; sınırlar kayıt sıklığına bağlı olduğundan yaklaşıktır.
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

    var averageSpeedKmh: Double? {
        duration > 0 ? distanceKm / (duration / 3600) : nil
    }

    /// Gezi boyunca harcanan batarya yüzdesi; gezi sırasında şarj olduysa ya da veri yoksa nil.
    var batteryUsedPercent: Double? {
        guard let startBattery, let endBattery, startBattery >= endBattery else { return nil }
        return (startBattery - endBattery) * 100
    }

    func energyKWh(capacityKWh: Double?) -> Double? {
        guard let used = batteryUsedPercent, let capacityKWh, capacityKWh > 0 else { return nil }
        return used / 100 * capacityKWh
    }

    /// kWh/100 km. Araç bataryayı tam yüzde olarak bildirdiğinden kısa gezilerde sonuç çok kabadır;
    /// bu yüzden en az `TripDeriver.minimumDistanceForConsumptionKm` mesafe aranır.
    func consumption(capacityKWh: Double?) -> Double? {
        guard distanceKm >= TripDeriver.minimumDistanceForConsumptionKm,
              let energy = energyKWh(capacityKWh: capacityKWh), energy > 0 else { return nil }
        return energy / distanceKm * 100
    }
}

nonisolated enum TripDeriver {
    /// Ardışık iki kayıt arası bundan uzunsa aradaki kilometre bir geziye yazılmaz.
    static let maximumGap: TimeInterval = 30 * 60
    /// Bundan kısa kilometre farkı gezi sayılmaz (sensör gürültüsü).
    static let minimumTripDistanceKm = 0.5
    static let minimumDistanceForConsumptionKm = 5.0

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

    /// Geziler arası ağırlıklı ortalama tüketim (kWh/100 km); hesaplanabilen gezi yoksa nil.
    static func averageConsumption(of trips: [DerivedTrip], capacityKWh: Double?) -> Double? {
        var energy = 0.0
        var distance = 0.0
        for trip in trips where trip.consumption(capacityKWh: capacityKWh) != nil {
            energy += trip.energyKWh(capacityKWh: capacityKWh) ?? 0
            distance += trip.distanceKm
        }
        return distance > 0 ? energy / distance * 100 : nil
    }
}
