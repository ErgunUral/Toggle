import Foundation
import Observation

/// Araçtan okunan bir ölçüm. Konum saklanmaz.
nonisolated struct HistoryPoint: Codable, Identifiable, Sendable {
    var date: Date
    var battery: Double?
    var rangeKm: Double?
    var odometerKm: Double?
    var outsideTemp: Double?
    var isCharging: Bool?

    var id: Date { date }
}

/// Canlı veri geldikçe ölçümleri cihazda saklar; seyahat grafiklerinin kaynağıdır.
/// Veri yalnızca uygulama açıkken kaydedildiğinden kayıtta boşluklar olabilir.
@MainActor @Observable
final class HistoryStore {
    private(set) var points: [HistoryPoint] = []

    private let fileURL: URL
    /// Aynı aralıkta gelen sık ölçümleri tek kayıtta tutar (araç zamanına göre).
    private let minimumInterval: TimeInterval = 5 * 60
    private let maximumPoints = 6000

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "history.json")
        load()
    }

    // MARK: Kayıt

    /// Canlı anlık görüntüyü kaydeder. Araç zamanı değişmediyse ya da son kayda çok yakınsa atlar.
    func record(_ snapshot: VehicleSnapshot) {
        guard snapshot.isLive else { return }
        // Araç zamanı yoksa kayıt sıralaması bozulacağından atlanır.
        guard let date = snapshot.updatedAt else {
            AppLog.debug(.refresh, "Geçmiş: kayıt atlandı (araç zamanı yok)")
            return
        }
        if let last = points.last, date.timeIntervalSince(last.date) < minimumInterval {
            AppLog.debug(.refresh, "Geçmiş: kayıt atlandı (son kayıttan \(Int(date.timeIntervalSince(last.date))) sn sonra)")
            return
        }
        points.append(HistoryPoint(
            date: date,
            battery: snapshot.battery,
            rangeKm: snapshot.range,
            odometerKm: snapshot.odometer,
            outsideTemp: snapshot.outside,
            isCharging: snapshot.isCharging
        ))
        if points.count > maximumPoints { points.removeFirst(points.count - maximumPoints) }
        AppLog.info(.refresh, "Geçmiş: kayıt eklendi (toplam \(points.count))")
        save()
    }

    func clear() {
        points.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        AppLog.info(.app, "Geçmiş kayıtları silindi")
    }

    // MARK: Türetilen veriler

    struct DailyDistances {
        /// Son `days` günün her günü için kilometre (kayıt olmayan günler 0).
        var days: [DailyDrive]
        /// 24 saatten uzun kayıtsız aralıklara düşen kilometre; günlere dağıtılamaz.
        var untrackedKm: Double
    }

    /// Ardışık kayıtların kilometre farkından günlük mesafeyi çıkarır.
    func dailyDistances(days count: Int = 7, calendar: Calendar = .current, now: Date = .now) -> DailyDistances {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today

        var perDay: [Date: Double] = [:]
        var untracked = 0.0
        let sorted = points.sorted { $0.date < $1.date }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            guard later.date >= windowStart,
                  let a = earlier.odometerKm, let b = later.odometerKm else { continue }
            let delta = b - a
            // Negatif ya da gerçekçi olmayan sıçramalar veri hatası sayılır.
            guard delta >= 0, delta < 1500 else { continue }
            if later.date.timeIntervalSince(earlier.date) > 24 * 3600 {
                untracked += delta
            } else {
                perDay[calendar.startOfDay(for: later.date), default: 0] += delta
            }
        }
        let bars = (0..<count).reversed().compactMap { offset -> DailyDrive? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyDrive(date: day, km: perDay[day] ?? 0)
        }
        return DailyDistances(days: bars, untrackedKm: untracked)
    }

    /// Son `days` gündeki batarya seviyesi ölçümleri.
    func batteryPoints(lastDays days: Int = 7, now: Date = .now) -> [HistoryPoint] {
        let start = now.addingTimeInterval(-Double(days) * 24 * 3600)
        return points.filter { $0.date >= start && $0.battery != nil }
    }

    /// Son `days` günde biten geziler, en yeni başta.
    func trips(lastDays days: Int, now: Date = .now) -> [DerivedTrip] {
        let start = now.addingTimeInterval(-Double(days) * 24 * 3600)
        return TripDeriver.trips(from: points)
            .filter { $0.end >= start }
            .sorted { $0.start > $1.start }
    }

    /// Son `days` günde biten şarj oturumları, en yeni başta.
    func chargeSessions(lastDays days: Int, now: Date = .now) -> [DerivedChargeSession] {
        let start = now.addingTimeInterval(-Double(days) * 24 * 3600)
        return ChargeDeriver.sessions(from: points)
            .filter { $0.end >= start }
            .sorted { $0.start > $1.start }
    }

    /// İki zaman arasındaki kayıtlar, eskiden yeniye.
    func points(from start: Date, to end: Date) -> [HistoryPoint] {
        points.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }

    // MARK: Dosya

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLog.debug(.app, "Geçmiş: kayıt dosyası yok")
            return
        }
        do {
            points = try JSONDecoder().decode([HistoryPoint].self, from: data)
            AppLog.info(.app, "Geçmiş: \(points.count) kayıt yüklendi")
        } catch {
            AppLog.error(.app, "Geçmiş: dosya okunamadı: \(AppLog.describe(error))")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(points).write(to: fileURL, options: .atomic)
        } catch {
            AppLog.error(.app, "Geçmiş: kaydedilemedi: \(AppLog.describe(error))")
        }
    }
}
