import SwiftUI
import CoreLocation

// MARK: - Renkler

/// Togg araç renkleri. Görsel adları PNG dosya adlarıyla eşleşir.
enum VehicleColor: String, CaseIterable, Identifiable {
    case blue, black, white, grey, beige, red, green, new_white
    case obsidian_black, obsidian_grey, obsidian_red, obsidian_green, obsidian_new_white

    static let spinFrameCount = 18

    var id: String { rawValue }

    /// API'deki ad ("BLUE", "OBSIDIAN_GREY") ile eşleşir; tanınmayan ad nil döner.
    init?(apiName: String) {
        let key = apiName.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "gray", with: "grey")
        self.init(rawValue: key)
    }

    var title: String {
        switch self {
        case .blue: "Gemlik · Mavi"
        case .black: "Oltu · Siyah"
        case .white: "Pamukkale · Beyaz"
        case .grey: "Kula · Gri"
        case .beige: "Kapadokya · Bej"
        case .red: "Anadolu · Kırmızı"
        case .green: "Ayder · Yeşil"
        case .new_white: "Urla · Yeni beyaz"
        case .obsidian_black: "Obsidiyen · Siyah"
        case .obsidian_grey: "Obsidiyen · Gri"
        case .obsidian_red: "Obsidiyen · Kırmızı"
        case .obsidian_green: "Obsidiyen · Yeşil"
        case .obsidian_new_white: "Obsidiyen · Yeni beyaz"
        }
    }

    /// 360° görsel yalnızca bazı renkler için var.
    var hasSpin: Bool {
        [.blue, .black, .obsidian_green, .obsidian_grey, .obsidian_red].contains(self)
    }

    var imageName: String { "car_\(rawValue)" }

    func spinFrame(_ index: Int) -> String {
        "spin_\(rawValue)_" + String(format: "%02d", index)
    }
}

// MARK: - Araç verisi

enum ClimateMode: String, CaseIterable, Identifiable {
    case auto, heat, cool

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .auto: "Otomatik"
        case .heat: "Isıt"
        case .cool: "Soğut"
        }
    }
}

struct TripStats {
    var distance: Double
    var average: Double?
    var energy: Double?
    var batteryPercent: Double?
    var note: String
    /// km/sa
    var averageSpeed: Double?
}

struct TirePressure {
    var frontLeft: Double?
    var frontRight: Double?
    var rearLeft: Double?
    var rearRight: Double?
}

/// Lastik sıcaklıkları (°C).
struct TireTemperatures {
    var frontLeft: Double?
    var frontRight: Double?
    var rearLeft: Double?
    var rearRight: Double?

    var hasValue: Bool {
        [frontLeft, frontRight, rearLeft, rearRight].contains { $0 != nil }
    }
}

/// Araç durumu. Varsayılan değerler örnek veridir; `isLive` true ise okunabilen
/// alanlar Togg'dan gelir, okunamayanlar nil kalır, geri kalan alanlar örnektir.
struct VehicleSnapshot {
    /// API'den yalnızca gerçekten gelen alanları taşıyan canlı başlangıç durumu.
    /// Örnek verilerin canlı ekranda görünmesini engeller.
    static var liveEmpty: VehicleSnapshot {
        var snapshot = VehicleSnapshot()
        snapshot.isLive = true
        snapshot.name = "Araç"
        snapshot.model = ""
        snapshot.edition = ""
        snapshot.year = 0
        snapshot.vin = ""
        snapshot.plate = nil
        snapshot.battery = nil
        snapshot.range = nil
        snapshot.batteryEnergyKWh = nil
        snapshot.odometer = nil
        snapshot.inside = nil
        snapshot.outside = nil
        snapshot.auxBattery = nil
        snapshot.internetQuotaIsLive = false
        snapshot.tires = TirePressure(frontLeft: nil, frontRight: nil, rearLeft: nil, rearRight: nil)
        snapshot.tireTemperatures = TireTemperatures()
        snapshot.brakeWarning = nil
        snapshot.engineWarning = nil
        snapshot.softwareVersion = nil
        snapshot.ownerType = nil
        snapshot.keySharingEnabled = nil
        snapshot.manufacturer = nil
        snapshot.internetUsedGB = 0
        snapshot.internetQuotaGB = 0
        snapshot.isCharging = nil
        snapshot.driveMode = nil
        snapshot.doorsLocked = false
        snapshot.trunkOpen = false
        snapshot.climateOn = false
        snapshot.currentTrip = TripStats(distance: 0, average: nil, energy: nil, batteryPercent: nil, note: "Canlı veri bekleniyor", averageSpeed: nil)
        snapshot.sinceCharge = TripStats(distance: 0, average: nil, energy: nil, batteryPercent: nil, note: "Canlı veri bekleniyor", averageSpeed: nil)
        snapshot.coordinate = nil
        snapshot.address = nil
        snapshot.updatedAt = nil
        return snapshot
    }

    var isLive = false
    /// Sürüş özetleri canlı veriden geldiyse true.
    var tripsAreLive = false

    var name = "T10X’İM"
    var model = "T10X"
    var edition = "V2 Uzun Menzil"
    var year = 2025
    var vin = "TRZ••••••••••1234"
    /// nil: plaka bilinmiyor (örnek modda da yok).
    var plate: String?

    var battery: Double? = 0.78
    var range: Double? = 365
    /// Bataryada kalan enerji (kWh). Canlı veride `batteryTotalEnergyValue`.
    var batteryEnergyKWh: Double? = 0.78 * 83.5
    var odometer: Double? = 12_840
    var inside: Double? = 26
    var outside: Double? = 24
    var auxBattery: Double? = 0.92
    var internetQuotaIsLive = false
    var tires = TirePressure(frontLeft: 36, frontRight: 36, rearLeft: 35, rearRight: 35)
    /// Yalnızca canlı veride dolar; örnek modda boştur.
    var tireTemperatures = TireTemperatures()
    /// nil: okunamadı (örnek modda da yok).
    var brakeWarning: Bool?
    var engineWarning: Bool?
    var softwareVersion: String?
    var ownerType: String?
    var keySharingEnabled: Bool?
    var manufacturer: String?
    var internetUsedGB = 3.2
    var internetQuotaGB = 10.0

    /// nil: şarj durumu okunamadı.
    var isCharging: Bool? = false
    var driveMode: String? = "Comfort"

    var doorsLocked = true
    var trunkOpen = false

    var climateOn = false
    var climateMode = ClimateMode.auto
    var targetTemperature = 22
    var defrost = false
    var steeringHeat = false
    var driverSeatHeat = false
    var passengerSeatHeat = false

    var coordinate: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: 41.0430, longitude: 29.0094)
    var address: String? = "Beşiktaş, İstanbul"

    var updatedAt: Date? = Date.now.addingTimeInterval(-6 * 60)

    /// Kalan enerjiden ve doluluktan çıkarılan kullanılabilir kapasite (kWh).
    var usableCapacityKWh: Double? {
        guard let energy = batteryEnergyKWh, let battery, battery > 0.05 else { return nil }
        return energy / battery
    }

    /// Kalan enerji ile son şarjdan beri ortalama tüketimden hesaplanan menzil (km).
    var realisticRange: Double? {
        // Canlı modda örnek tüketim değeriyle hesap yapılmaz.
        guard !isLive || tripsAreLive,
              let energy = batteryEnergyKWh,
              let average = sinceCharge.average ?? currentTrip.average,
              average > 0 else { return nil }
        return energy / average * 100
    }

    var currentTrip = TripStats(distance: 18.4, average: 16.8, energy: 3.1, batteryPercent: 3.5, note: "Bugün 08:12 başladı", averageSpeed: 36)
    var sinceCharge = TripStats(distance: 142.6, average: 17.4, energy: 24.8, batteryPercent: 28, note: "Son şarj 2 gün önce", averageSpeed: 52)
}

// MARK: - Örnek veri

struct DailyDrive: Identifiable {
    let date: Date
    let km: Double
    var id: Date { date }
}

struct ChargeSession: Identifiable {
    let id = UUID()
    let place: String
    let date: Date
    let energy: Double
    let cost: Double
    let isFast: Bool
}

struct GarageNotification: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let date: Date
}

struct ServiceRecord: Identifiable {
    let id = UUID()
    let title: String
    let place: String
    let date: Date
}

struct SubscriptionItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isActive: Bool
}

enum SampleData {
    private static func daysAgo(_ days: Int, hour: Int = 12) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static let weeklyDrives: [DailyDrive] = [64, 22, 0, 98, 41, 18, 35].enumerated().map { offset, km in
        DailyDrive(date: daysAgo(6 - offset), km: km)
    }

    static let chargeSessions: [ChargeSession] = [
        ChargeSession(place: "Trugo · Zorlu Center", date: daysAgo(2, hour: 19), energy: 41.2, cost: 412, isFast: true),
        ChargeSession(place: "Ev · AC Wallbox", date: daysAgo(6, hour: 23), energy: 36.8, cost: 98, isFast: false),
        ChargeSession(place: "Trugo · Gebze", date: daysAgo(11, hour: 14), energy: 52.4, cost: 524, isFast: true),
    ]

    static let notifications: [GarageNotification] = [
        GarageNotification(title: "Şarj tamamlandı", detail: "Batarya %80 seviyesine ulaştı.", symbol: "bolt.fill", date: daysAgo(2, hour: 20)),
        GarageNotification(title: "Yazılım güncellemesi", detail: "Yeni sürüm kurulmaya hazır.", symbol: "arrow.down.circle", date: daysAgo(4, hour: 9)),
        GarageNotification(title: "Lastik basıncı", detail: "Sol ön lastik basıncı normale döndü.", symbol: "gauge.with.dots.needle.33percent", date: daysAgo(8, hour: 8)),
    ]

    static let serviceRecords: [ServiceRecord] = [
        ServiceRecord(title: "Periyodik bakım · 10.000 km", place: "Togg Servis · Ümraniye", date: daysAgo(40)),
        ServiceRecord(title: "Polen filtresi değişimi", place: "Togg Servis · Ümraniye", date: daysAgo(40)),
    ]

    static let subscriptions: [SubscriptionItem] = [
        SubscriptionItem(title: "Bağlantı paketi", detail: "10 GB / ay · yenileme 1 Kasım", isActive: true),
        SubscriptionItem(title: "Uzaktan kontrol", detail: "Sürekli aktif", isActive: true),
        SubscriptionItem(title: "Premium navigasyon", detail: "Abone değilsin", isActive: false),
    ]

    static let specs: [(String, String)] = [
        ("Model", "Togg T10X"),
        ("Versiyon", "V2 Uzun Menzil"),
        ("Model yılı", "2025"),
        ("Batarya kapasitesi", "88,5 kWh"),
        ("WLTP menzil", "523 km"),
        ("Azami güç", "160 kW"),
        ("Azami tork", "350 Nm"),
        ("AC şarj", "11 kW"),
        ("DC şarj", "150 kW"),
    ]
}
