import Foundation

/// Togg sunucusundaki DriveExperience analizlerinin türleri ve dönemleri.
nonisolated enum AnalyticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case annual = "Annual"

    var id: String { rawValue }
}

/// Bir dönem bloğundaki ölçümler. Sunucu alan adlarını sürümler arasında değiştirdiğinden
/// her değer birkaç olası anahtardan okunur; yanıtta yoksa nil kalır.
nonisolated struct ServerMetrics: Sendable, Equatable {
    var distanceKm: Double?
    var consumedKWh: Double?
    var averageKWhPer100Km: Double?
    var journeyCount: Double?
    var drivingHours: Double?
    var economyScore: Double?
    var chargeCount: Double?
    var addedKWh: Double?

    init(_ dict: [String: Any]) {
        distanceKm = ServerAnalytics.number(dict, "total_distance_km", "total_km", "km_total", "distance_km")
        consumedKWh = ServerAnalytics.number(dict, "total_kwh_consumed", "total_consumption_kwh", "consumption_kwh", "kwh_consumed")
        averageKWhPer100Km = ServerAnalytics.number(dict, "avg_consumption_per_100km", "avg_kwh_per_100km", "monthly_average_consumption_kwh")
        journeyCount = ServerAnalytics.number(dict, "journey_count", "total_journeys", "drive_count")
        drivingHours = ServerAnalytics.number(dict, "driving_time_hours")
        economyScore = ServerAnalytics.number(dict, "avg_economy_score", "economy_score", "journey_score")
        chargeCount = ServerAnalytics.number(dict, "monthly_charges", "total_sessions")
        addedKWh = ServerAnalytics.number(dict, "total_kwh_added", "total_energy_kwh")
    }
}

/// Özet sayfasındaki adlandırılmış dönem bloğu.
nonisolated struct ServerInsightBlock: Sendable, Identifiable, Equatable {
    let key: String
    let title: String
    let metrics: ServerMetrics
    var id: String { key }
}

/// Tek bir sürüş ya da şarj kaydı.
nonisolated struct ServerRecord: Sendable, Identifiable, Equatable {
    let id: String
    let date: Date?
    let distanceKm: Double?
    let consumedKWh: Double?
    let addedKWh: Double?
    let socStartPercent: Double?
    let socEndPercent: Double?
    let durationMinutes: Double?

    init(_ dict: [String: Any], fallbackIndex: Int) {
        let rawID = ServerAnalytics.text(dict, "charge_id", "journey_id", "trip_id", "id")
        id = rawID ?? "kayit-\(fallbackIndex)"
        date = ServerAnalytics.date(dict)
        distanceKm = ServerAnalytics.number(dict, "total_distance_km", "distance_km")
        consumedKWh = ServerAnalytics.number(dict, "total_kwh_consumed", "kwh_consumed")
        addedKWh = ServerAnalytics.number(dict, "kwh_added")
        socStartPercent = ServerAnalytics.number(dict, "soc_start_pct")
        socEndPercent = ServerAnalytics.number(dict, "soc_end_pct")
        durationMinutes = ServerAnalytics.number(dict, "duration_min")
    }
}

nonisolated struct ServerRecordPage: Sendable, Equatable {
    var records: [ServerRecord]
    var totals: ServerMetrics
    var hasMore: Bool
}

/// Sunucu yanıtlarını çözen saf işlevler.
nonisolated enum ServerAnalytics {
    static let summaryBlocks: [(key: String, title: String)] = [
        ("this_month", "Son 30 gün"),
        ("last_month", "Önceki dönem"),
        ("last_month_calendar", "Önceki takvim ayı"),
        ("all_time", "Tüm zamanlar"),
    ]

    /// Yanıt bazen `data` içine sarılı gelir.
    static func unwrap(_ json: [String: Any]) -> [String: Any] {
        (json["data"] as? [String: Any]) ?? json
    }

    static func insights(from json: [String: Any]) -> [ServerInsightBlock] {
        let doc = unwrap(json)
        return summaryBlocks.compactMap { key, title in
            (doc[key] as? [String: Any]).map { ServerInsightBlock(key: key, title: title, metrics: ServerMetrics($0)) }
        }
    }

    static func page(from json: [String: Any], isCharge: Bool) -> ServerRecordPage {
        let doc = unwrap(json)
        let rows = (doc[isCharge ? "charges" : "journeys"] as? [[String: Any]]) ?? []
        // Aynı kimlikli kayıtlar tekrarlanabilir (sayfa kayması); ilkini tut.
        var seen = Set<String>()
        let records = rows.enumerated()
            .map { ServerRecord($1, fallbackIndex: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let pagination = doc[isCharge ? "charges_pagination" : "journeys_pagination"] as? [String: Any]
        let hasMore = (pagination?["has_more"] as? Bool) ?? (doc["has_more"] as? Bool) ?? false
        let totalsSource = (doc["totals"] as? [String: Any]) ?? (doc["summary"] as? [String: Any]) ?? doc
        return ServerRecordPage(records: records, totals: ServerMetrics(totalsSource), hasMore: hasMore)
    }

    /// İlk sonlu sayısal değer; metin olarak gelen sayılar da kabul edilir.
    static func number(_ dict: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            let value: Double?
            switch dict[key] {
            case let number as NSNumber: value = number.doubleValue
            case let string as String: value = Double(string)
            default: value = nil
            }
            if let value, value.isFinite { return value }
        }
        return nil
    }

    static func text(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            switch dict[key] {
            case let string as String where !string.isEmpty: return string
            case let number as NSNumber: return number.stringValue
            default: continue
            }
        }
        return nil
    }

    /// `start_ts`, `date` + `start_time` ya da `event_date` alanlarından zamanı çıkarır.
    static func date(_ dict: [String: Any]) -> Date? {
        if let stamp = text(dict, "start_ts") { return parseDate(stamp) }
        if let day = text(dict, "date"), let time = text(dict, "start_time") { return parseDate("\(day)T\(time)") }
        return text(dict, "start_time", "event_date").flatMap(parseDate)
    }

    static func parseDate(_ stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        if let date = fractional.date(from: stamp) ?? plain.date(from: stamp) { return date }
        // Saat dilimi olmayan ("2026-10-16T08:12:00") ve yalnızca tarih ("2026-10-16") biçimleri.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: stamp) { return date }
        }
        return nil
    }
}
