import Foundation

/// Bir dönemdeki gezilerin özeti. Yalnızca ölçülmüş değerlerden (kilometre sayacı, batarya yüzdesi,
/// süre) hesaplanır; enerji (kWh) ya da tüketim tahmini içermez.
nonisolated struct PeriodSummary: Sendable {
    let tripCount: Int
    let distanceKm: Double
    let duration: TimeInterval
    /// Batarya verisi olan gezilerde toplam düşen yüzde puanı ve bu gezilerin toplam mesafesi.
    let batteryUsedPercent: Double
    let batteryTrackedKm: Double

    var averageSpeedKmh: Double? {
        duration > 0 ? distanceKm / (duration / 3600) : nil
    }

    /// 100 km'de kullanılan batarya yüzdesi; batarya verisi olan yeterli gezi yoksa nil.
    var batteryPercentPer100Km: Double? {
        batteryTrackedKm >= Self.minimumTrackedKm ? batteryUsedPercent / batteryTrackedKm * 100 : nil
    }

    /// 0...100 ekonomi puanı. 100 km'de %12 ve altı batarya kullanımı 100, %32 ve üstü 0 puandır.
    /// Bu uygulamaya özgü, tahmini bir ölçektir; Togg'un hesapladığı puan değildir.
    var economyScore: Double? {
        guard let used = batteryPercentPer100Km else { return nil }
        let score = (Self.worstPercentPer100Km - used) / (Self.worstPercentPer100Km - Self.bestPercentPer100Km) * 100
        return min(100, max(0, score))
    }

    static let bestPercentPer100Km = 12.0
    static let worstPercentPer100Km = 32.0
    /// Bundan kısa toplam mesafeden puan çıkarılmaz (yüzde yuvarlaması çok etkili olur).
    static let minimumTrackedKm = 10.0

    init(trips: [DerivedTrip]) {
        tripCount = trips.count
        distanceKm = trips.reduce(0) { $0 + $1.distanceKm }
        duration = trips.reduce(0) { $0 + $1.duration }
        let tracked = trips.filter { $0.batteryUsedPercent != nil }
        batteryUsedPercent = tracked.reduce(0) { $0 + ($1.batteryUsedPercent ?? 0) }
        batteryTrackedKm = tracked.reduce(0) { $0 + $1.distanceKm }
    }
}
