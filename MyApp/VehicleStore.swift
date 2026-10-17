import Foundation
import Security
import CryptoKit

// MARK: - Modeller

/// Araç listesindeki bir kayıt.
nonisolated struct VehicleSummary: Identifiable, Hashable, Sendable {
    let vin: String
    let name: String
    let plate: String
    let model: String
    let edition: String
    /// Araç listesindeki renk adı. VehicleInfo'daki `color` ile çeliştiğinde (BLUE ↔ Grey)
    /// liste doğru çıktığından renk için birincil kaynaktır.
    let color: String?
    /// Araç listesindeki model yılı. VehicleInfo'daki `year` yanlış geldiğinden bu kullanılır.
    let year: String?
    /// Android 1.0.13'ün de okuduğu ek alanlar; liste yanıtında yoksa nil.
    let trimLevel: String?
    let version: String?
    let ownerType: String?
    let keySharingEnabled: Bool?
    let manufacturer: String?
    var id: String { vin }
}

/// VehicleInfo yanıtındaki bir sürüş özeti. Mesafe metreden kilometreye çevrilmiş halde tutulur.
nonisolated struct TripInfo: Sendable {
    var distanceKm: Double
    var averageConsumption: Double?
    /// km/sa. Mesafe ve süreyle tutarlı çıktığı görüldü (178 km / 8 sa 16 dk ≈ 21).
    var averageSpeedKmh: Double?
    var durationMinutes: Int?
    var updatedOn: Date?
}

/// Araç telemetrisinden okunan internet kullanım kotası.
nonisolated struct InternetQuota: Sendable, Equatable {
    let remainingGB: Double
    let totalGB: Double

    var usedGB: Double { totalGB - remainingGB }
    var fractionRemaining: Double { remainingGB / totalGB }
}

/// VehicleInfo yanıtından okunan, salt okunur araç durumu.
nonisolated struct VehicleState: Sendable {
    var vin: String
    var name: String
    var model: String
    var edition: String
    var battery: Double?
    var range: Double?
    var odometer: Double?
    var inside: Double?
    var outside: Double?
    var auxBattery: Double?
    var internetQuota: InternetQuota?
    var latitude: Double?
    var longitude: Double?
    var updatedOn: Date?
    var tiresFrontPSI: (Double?, Double?) = (nil, nil)
    var tiresRearPSI: (Double?, Double?) = (nil, nil)
    var currentTrip: TripInfo?
    var lastChargeTrip: TripInfo?
    /// `lastTripInfo.myTrip`: kullanıcının kendi sıfırladığı yolculuk sayacı; her araçta gelmeyebilir.
    var myTrip: TripInfo?
    /// `batteryTotalEnergyValue`. Değerin anlamı kesin değil: %72 doluluktayken 60,16 geldi;
    /// 60,16 / 0,72 ≈ 83,6 kWh (T10X'in kullanılabilir kapasitesine yakın) olduğundan
    /// kalan enerji (kWh) olarak yorumlanır.
    var batteryEnergyKWh: Double?
    /// Araç rengi, API'deki adıyla (örn. "BLUE").
    var colorName: String?
    var chargeMode: String?
    var driveMode: String?
    /// °C (ön sol/sağ, arka sol/sağ). Birim varsayımdır; park halindeki araçta 17–19 geldi.
    var tireTempsFrontC: (Double?, Double?) = (nil, nil)
    var tireTempsRearC: (Double?, Double?) = (nil, nil)
    /// API anahtarı `breakWarning` (fren uyarısı) ve `engineWarning`; nil: okunamadı.
    var brakeWarning: Bool?
    var engineWarning: Bool?
    /// `versionInfo.version`. Aracın mı yoksa servisin sürümü mü olduğu kesin değil.
    var softwareVersion: String?
}

extension VehicleState {
    /// APK'daki desenle aynı: şarj modu bir AC/DC şarj değeri ise şarj oluyordur.
    /// nil: şarj modu okunamadı.
    nonisolated var isCharging: Bool? {
        chargeMode.map {
            $0.range(
                of: "^(CHRGMODE_CHARGE|(CHARGEMODE_)?(AC_CHARGING|DC_CHARGING|CHARGING_AC|CHARGING_DC|CHARGING))$",
                options: .regularExpression
            ) != nil
        }
    }
}

nonisolated enum ServiceError: LocalizedError {
    case notSignedIn, sessionExpired, cancelled
    case http(Int)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Önce Togg ID ile giriş yap."
        case .sessionExpired: "Oturum süresi doldu; tekrar giriş yap."
        case .cancelled: "Giriş iptal edildi."
        case .http(let code): "Araç servisi HTTP \(code) döndürdü."
        case .badResponse(let text): text
        }
    }
}

// MARK: - Keychain

/// Oturum jetonlarını Keychain'de saklar. Jeton değerleri günlüğe yazılmaz.
private nonisolated enum Keychain {
    private static let service = "garajim.tokens"

    static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            AppLog.debug(.auth, "Keychain: oturum kaydedildi (\(data.count) bayt)")
        } else {
            AppLog.error(.auth, "Keychain: kayıt başarısız, OSStatus=\(status)")
        }
    }

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            AppLog.debug(.auth, "Keychain: kayıtlı oturum bulundu")
            return result as? Data
        case errSecItemNotFound:
            AppLog.info(.auth, "Keychain: kayıtlı oturum yok")
            return nil
        default:
            AppLog.error(.auth, "Keychain: okuma başarısız, OSStatus=\(status)")
            return nil
        }
    }

    static func delete() {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
        AppLog.debug(.auth, "Keychain: oturum silindi, OSStatus=\(status)")
    }
}

private nonisolated struct Tokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

// MARK: - Servis

/// Togg ID girişi ve salt okunur araç sorguları. Araca komut göndermez.
actor TogglService {
    /// Uygulama ve Siri/Kısayol aynı örneği paylaşır; böylece token yenilemeleri çakışmaz.
    static let shared = TogglService()

    private let authURL = URL(string: "https://toggid.togg.cloud/auth/realms/toggid/protocol/openid-connect/auth")!
    private let tokenURL = URL(string: "https://toggid.togg.cloud/auth/realms/toggid/protocol/openid-connect/token")!
    private let apiBase = "https://tva-api.togg.cloud"
    private let clientID = "super-app"
    private let redirect = "superapp://prod/callback"

    private var tokens: Tokens? = {
        guard let data = Keychain.load() else { return nil }
        do {
            return try JSONDecoder().decode(Tokens.self, from: data)
        } catch {
            AppLog.error(.auth, "Keychain: oturum verisi çözülemedi: \(AppLog.describe(error))")
            return nil
        }
    }()

    /// Devam eden token yenilemesi.
    private var refreshTask: Task<Void, Error>?

    var isSignedIn: Bool { tokens != nil }

    // MARK: Giriş

    /// PKCE adımları için kullanılacak giriş adresini ve doğrulama değerlerini üretir.
    func prepareLogin() -> (url: URL, state: String, verifier: String) {
        let state = Self.random()
        let verifier = Self.random()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: Self.random()),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        AppLog.info(.auth, "Giriş adresi hazırlandı: host=\(authURL.host() ?? "-"), PKCE=S256, client_id=\(clientID)")
        return (comps.url!, state, verifier)
    }

    func completeLogin(callback: URL, state: String, verifier: String) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        AppLog.info(.auth, "Callback alındı: scheme=\(callback.scheme ?? "-"), parametreler=[\(items.map(\.name).sorted().joined(separator: ","))]")
        guard value("error") == nil else {
            AppLog.error(.auth, "Sağlayıcı hata döndürdü: error=\(value("error") ?? "-"), error_description=\(value("error_description") ?? "-")")
            throw ServiceError.badResponse("Togg ID girişi tamamlanmadı.")
        }
        guard value("state") == state else {
            AppLog.error(.auth, "state doğrulaması başarısız (callback state=\(value("state") == nil ? "yok" : "farklı"))")
            throw ServiceError.badResponse("Giriş doğrulanamadı.")
        }
        guard let code = value("code"), !code.isEmpty, code.count < 10_000 else {
            AppLog.error(.auth, "code geçersiz (uzunluk=\(value("code")?.count ?? 0))")
            throw ServiceError.badResponse("Giriş kodu alınamadı.")
        }
        AppLog.debug(.auth, "state doğrulandı, code uzunluğu=\(code.count); token değişimi başlıyor")
        try await exchange([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
            "code": code,
            "code_verifier": verifier,
        ])
    }

    func signOut() {
        AppLog.info(.auth, "Oturum kapatılıyor, bellekteki ve Keychain'deki jetonlar siliniyor")
        tokens = nil
        Keychain.delete()
    }

    private func exchange(_ form: [String: String]) async throws {
        let grant = form["grant_type"] ?? "-"
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let started = ContinuousClock.now
        AppLog.debug(.network, "POST token (grant_type=\(grant))")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AppLog.error(.network, "POST token ağ hatası (\(AppLog.ms(since: started))): \(AppLog.describe(error))")
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info(.network, "POST token (grant_type=\(grant)) → HTTP \(status), \(data.count) bayt, \(AppLog.ms(since: started))")

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let json, let access = json["access_token"] as? String else {
            AppLog.error(.auth, "Token yanıtı geçersiz: HTTP \(status), error=\(json?["error"] as? String ?? "-"), error_description=\(json?["error_description"] as? String ?? "-"), anahtarlar=\(AppLog.shape(json))")
            // Sunucu refresh token'ı reddettiyse oturum gerçekten bitmiştir.
            if grant == "refresh_token", json?["error"] as? String == "invalid_grant" {
                signOut()
                throw ServiceError.sessionExpired
            }
            throw ServiceError.badResponse("Oturum açılamadı; yeniden giriş yap.")
        }
        let lifetime = (json["expires_in"] as? Double) ?? 300
        let newRefresh = json["refresh_token"] as? String
        let new = Tokens(
            accessToken: access,
            refreshToken: newRefresh ?? tokens?.refreshToken,
            expiresAt: Date().addingTimeInterval(lifetime)
        )
        tokens = new
        AppLog.info(.auth, "Oturum alındı: expires_in=\(Int(lifetime)) sn, yeni refresh_token=\(newRefresh == nil ? "yok (eskisi korundu)" : "var")")
        if let encoded = try? JSONEncoder().encode(new) { Keychain.save(encoded) }
    }

    private func accessToken() async throws -> String {
        guard let current = tokens else {
            AppLog.warning(.auth, "Erişim anahtarı istendi ama oturum yok")
            throw ServiceError.notSignedIn
        }
        let remaining = Int(current.expiresAt.timeIntervalSinceNow)
        if remaining > 60 {
            AppLog.debug(.auth, "Erişim anahtarı geçerli (kalan \(remaining) sn)")
            return current.accessToken
        }
        AppLog.info(.auth, "Erişim anahtarının süresi dolmak üzere (kalan \(remaining) sn); yenilenecek")
        guard let refresh = current.refreshToken, !refresh.isEmpty else {
            AppLog.error(.auth, "refresh_token yok; oturum kapatılıyor")
            signOut()
            throw ServiceError.sessionExpired
        }
        // Eşzamanlı istekler tek bir yenilemeyi paylaşır; refresh token rotasyonunda
        // ikinci kullanım oturumu geçersiz kılabilir.
        let task = refreshTask ?? Task {
            try await exchange(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh])
        }
        refreshTask = task
        do {
            try await task.value
            refreshTask = nil
        } catch ServiceError.sessionExpired {
            refreshTask = nil
            throw ServiceError.sessionExpired
        } catch {
            refreshTask = nil
            AppLog.error(.auth, "Oturum yenilenemedi: \(AppLog.describe(error))")
            throw ServiceError.badResponse("Oturum yenilenemedi; yeniden giriş yap. Ağ bağlantını da kontrol et.")
        }
        return tokens?.accessToken ?? ""
    }

    // MARK: Okuma

    /// İstek adresindeki VIN'i maskeler.
    private static func redact(_ path: String) -> String {
        // VIN hem sorgu parametresinde (`vin=`) hem de yolda geçebilir.
        path.replacing(/[A-HJ-NPR-Z0-9]{17}/) { AppLog.maskVIN(String($0.output)) }
    }

    private func get(_ path: String, base: String? = nil, extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let label = Self.redact(path)
        var request = URLRequest(url: URL(string: (base ?? apiBase) + path)!)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("TR", forHTTPHeaderField: "language")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }

        let started = ContinuousClock.now
        AppLog.debug(.network, "GET \(label)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AppLog.error(.network, "GET \(label) ağ hatası (\(AppLog.ms(since: started))): \(AppLog.describe(error))")
            throw error
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info(.network, "GET \(label) → HTTP \(code), \(data.count) bayt, \(AppLog.ms(since: started))")
        if code == 401 {
            AppLog.warning(.network, "401: erişim anahtarı reddedildi")
            throw ServiceError.sessionExpired
        }
        guard (200..<300).contains(code) else {
            AppLog.error(.network, "Beklenmeyen durum kodu \(code) (\(label))")
            throw ServiceError.http(code)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            AppLog.error(.parse, "Yanıt bir JSON nesnesi değil (\(data.count) bayt) (\(label))")
            throw ServiceError.badResponse("Servis beklenen formatta yanıt vermedi.")
        }
        AppLog.debug(.parse, "Yanıt yapısı (\(label)): \(AppLog.shape(json))")
        return json
    }

    /// Verilen anahtarlardan ilk dolu metin ya da sayı değerini döndürür (sayılar metne çevrilir).
    private static func text(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            let value: String?
            switch dict[key] {
            case let string as String: value = string.trimmingCharacters(in: .whitespaces)
            case let number as NSNumber: value = number.stringValue
            default: value = nil
            }
            if let value, !value.isEmpty { return value }
        }
        return nil
    }

    func vehicles() async throws -> [VehicleSummary] {
        let json = try await get("/vin-manage/api/v1/Vin/retrieveOwnerAndFriendVins")
        guard json["ownedVins"] != nil || json["friendVins"] != nil else {
            AppLog.error(.parse, "Araç listesinde ownedVins/friendVins yok; üst düzey anahtarlar=\(json.keys.sorted())")
            throw ServiceError.badResponse("Araç listesi beklenen formatta değil.")
        }
        var seen = Set<String>()
        var result: [VehicleSummary] = []
        var skipped = 0
        for key in ["ownedVins", "friendVins"] {
            let entries = json[key] as? [Any] ?? []
            AppLog.debug(.parse, "\(key): \(entries.count) kayıt")
            for entry in entries {
                let dict = entry as? [String: Any] ?? ["vin": "\(entry)"]
                let vin = (dict["vin"] as? String) ?? (dict["vinNumber"] as? String) ?? ""
                AppLog.debug(.parse, "\(key): liste rengi=\(dict["color"] ?? "yok"), model=\(dict["model"] ?? "yok"), yıl=\(dict["year"] ?? "yok"), sahiplik=\(dict["ownerType"] ?? "yok"), anahtar paylaşımı=\(dict["keysharingEnabled"] ?? "yok"), üretici=\(dict["manufacture"] ?? "yok")")
                guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil,
                      seen.insert(vin).inserted else {
                    skipped += 1
                    AppLog.debug(.parse, "\(key): VIN atlandı (geçersiz biçim ya da yinelenen, uzunluk=\(vin.count))")
                    continue
                }
                result.append(VehicleSummary(
                    vin: vin,
                    name: dict["name"] as? String ?? "",
                    plate: dict["plateNumber"] as? String ?? "",
                    model: dict["model"] as? String ?? "T10X",
                    edition: Self.text(dict, "edition", "trimLevel", "version") ?? "",
                    color: dict["color"] as? String,
                    year: Self.text(dict, "year", "modelYear", "vehicleModelYear"),
                    trimLevel: Self.text(dict, "trimLevel"),
                    version: Self.text(dict, "version"),
                    ownerType: dict["ownerType"] as? String,
                    keySharingEnabled: dict["keysharingEnabled"] as? Bool,
                    manufacturer: dict["manufacture"] as? String
                ))
            }
        }
        AppLog.info(.parse, "Araç listesi: \(result.count) geçerli, \(skipped) atlanan → \(result.map { AppLog.maskVIN($0.vin) })")
        return result
    }

    func state(for vehicle: VehicleSummary) async throws -> VehicleState {
        // Yalnızca hesabın araç listesindeki VIN sorgulanır.
        let json = try await get("/info/api/v2/VehicleInfo?vin=\(vehicle.vin)")
        guard let t = json["telemetry"] as? [String: Any] else {
            AppLog.error(.parse, "Yanıtta 'telemetry' yok; üst düzey anahtarlar=\(json.keys.sorted())")
            throw ServiceError.badResponse("Araç verisi beklenen formatta değil.")
        }
        func num(_ any: Any?) -> Double? {
            if let n = any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
            // Virgüllü ondalık gelirse de okunur.
            if let s = any as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        func at(_ root: Any?, _ path: String...) -> Any? {
            var cur = root
            for key in path { cur = (cur as? [String: Any])?[key] }
            return cur
        }
        let odo = at(t, "odometerStatus", "odometerStatusContent")
        let loc = at(t, "location", "content")
        let tires = at(t, "tirePressure", "content")
        func psi(_ a: Any?, _ key: String) -> Double? {
            num(at(a, key, key + "Value")).map { $0 * 0.145038 }
        }
        var state = VehicleState(
            vin: vehicle.vin,
            name: vehicle.name.isEmpty ? "T10X’İM" : vehicle.name,
            model: vehicle.model,
            edition: vehicle.edition,
            battery: num(at(t, "battery", "content", "batteryStateOfCharge", "batteryStateOfChargeValue")),
            range: num(at(t, "vehicleRange", "content", "estRange", "range")),
            // Kilometre sayacı metre cinsinden gelir.
            odometer: num(at(odo, "odometer", "odometerValue")).map { $0 / 1000 },
            inside: num(at(odo, "insideTemp", "insideTempValue")),
            outside: num(at(odo, "outsideTemp", "outsideTempValue")),
            auxBattery: num(at(t, "batteryPowerStatus", "batteryPowerStatusContent",
                               "lowVoltageStateOfChargeValue", "lowVoltageStateOfChargeValue")),
            latitude: num(at(loc, "latitude", "latitudeValue")),
            longitude: num(at(loc, "longitude", "longitudeValue"))
        )
        state.tiresFrontPSI = (psi(tires, "frontLeft"), psi(tires, "frontRight"))
        state.tiresRearPSI = (psi(tires, "rearLeft"), psi(tires, "rearRight"))

        func parseDate(_ stamp: String?) -> Date? {
            guard let stamp else { return nil }
            if let date = try? Date.ISO8601FormatStyle().parse(stamp) { return date }
            return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp)
        }
        let stamp = (t["updatedOn"] as? String) ?? (json["timestamp"] as? String)
        state.updatedOn = parseDate(stamp)
        AppLog.debug(.parse, "Zaman damgası: ham=\(stamp ?? "yok") → \(state.updatedOn == nil ? "çözülemedi" : "çözüldü")")

        // Sürüş özetleri: mesafe metre, süre saat+dakika, ortalama tüketim kWh/100 km.
        func trip(_ key: String) -> TripInfo? {
            guard let dict = at(json, "lastTripInfo", key) as? [String: Any],
                  let meters = num(dict["distance"]) else { return nil }
            let minutes = (num(at(dict, "duration", "hours")) ?? 0) * 60 + (num(at(dict, "duration", "minutes")) ?? 0)
            return TripInfo(
                distanceKm: meters / 1000,
                averageConsumption: num(dict["avgConsumptions"]),
                averageSpeedKmh: num(dict["avgSpeed"]),
                durationMinutes: Int(minutes),
                updatedOn: parseDate(dict["updatedOn"] as? String)
            )
        }
        state.currentTrip = trip("currentTrip")
        state.lastChargeTrip = trip("lastChargeTrip")
        state.myTrip = trip("myTrip")
        state.batteryEnergyKWh = num(at(t, "battery", "content", "batteryTotalEnergy", "batteryTotalEnergyValue"))
        // Liste rengi öncelikli; VehicleInfo'daki renk yanlış olabiliyor.
        state.colorName = vehicle.color ?? (json["color"] as? String)
        state.chargeMode = at(t, "obcState", "content", "chargeMode", "chargeModeEnumValue") as? String
        state.driveMode = at(t, "driveMode", "content", "driveModeState", "driveMode") as? String

        let tireTemps = at(t, "tireTemperature", "tireTemperatureContent")
        func tireTemp(_ position: String) -> Double? {
            num(at(tireTemps, position + "TireTemp", position + "TireTempValue"))
        }
        state.tireTempsFrontC = (tireTemp("frontLeft"), tireTemp("frontRight"))
        state.tireTempsRearC = (tireTemp("rearLeft"), tireTemp("rearRight"))
        state.brakeWarning = t["breakWarning"] as? Bool
        state.engineWarning = t["engineWarning"] as? Bool
        state.softwareVersion = at(json, "versionInfo", "version") as? String
        state.internetQuota = Self.internetQuota(from: json)
        AppLog.debug(.parse, "Sürüş özetleri: güncel=\(state.currentTrip == nil ? "yok" : "var"), sonŞarj=\(state.lastChargeTrip == nil ? "yok" : "var"); şarj modu=\(state.chargeMode ?? "yok"); sürüş modu=\(state.driveMode ?? "yok"); batarya enerjisi=\(state.batteryEnergyKWh.map { String(format: "%.2f kWh", $0) } ?? "yok") (ham), renk=\(state.colorName ?? "yok")")
        Self.logFieldSummary(state)
        Self.logRawValues(json: json, telemetry: t)
        Self.logResponseShape(json: json)
        return state
    }

    /// APK'daki kota çözümleme davranışıyla uyumlu olarak kalan internet kotasını çıkarır.
    /// `dataVolume` yüzde olarak gelirse 100'lük bir kota gibi tutulur; aksi halde
    /// `dataUsage` veya `internetUsage` içindeki GB alanları kullanılır.
    private static func internetQuota(from json: [String: Any]) -> InternetQuota? {
        func number(_ value: Any?) -> Double? {
            guard let value else { return nil }
            if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                return number.doubleValue
            }
            if let string = value as? String {
                return Double(string.replacingOccurrences(of: ",", with: "."))
            }
            return nil
        }

        if let remainingPercent = number(json["dataVolume"]), (0...100).contains(remainingPercent) {
            return InternetQuota(remainingGB: remainingPercent, totalGB: 100)
        }

        let usage = (json["dataUsage"] as? [String: Any])
            ?? (json["internetUsage"] as? [String: Any])
        guard let usage else { return nil }

        let total = number(usage["totalGb"]) ?? number(usage["dataLimitGb"])
        let remaining = number(usage["remainingGb"])
        let used = number(usage["usedGb"]) ?? number(usage["dataUsedGb"])
        guard let total, total > 0 else { return nil }

        let remainingGB = remaining ?? used.map { total - $0 }
        guard let remainingGB, (0...total).contains(remainingGB) else { return nil }
        return InternetQuota(remainingGB: remainingGB, totalGB: total)
    }

    /// DriveExperience özet bloklarını okur (`insightsDashboard`).
    func insights(vin: String) async throws -> [ServerInsightBlock] {
        let json = try await get("/info/api/v1/DriveExperience/\(vin)/insightsDashboard")
        return ServerAnalytics.insights(from: json)
    }

    /// Sunucudaki sürüş ya da şarj kayıtlarının bir sayfasını okur (sayfa başına 20 kayıt).
    func records(vin: String, isCharge: Bool, period: AnalyticsPeriod, offset: Int) async throws -> ServerRecordPage {
        let overview = isCharge ? "chargingOverview" : "journeysOverview"
        let json = try await get("/info/api/v1/DriveExperience/\(vin)/\(overview)\(period.rawValue)?limit=20&offset=\(offset)")
        return ServerAnalytics.page(from: json, isCharge: isCharge)
    }

    /// APK'deki Certificates/GetCertificate çağrısının iOS karşılığı.
    /// Sertifika yalnızca Togg ID oturumuyla ve hesabın sahip olduğu VIN için istenir.
    func digitalCertificate(vin: String, phonePublicKey: String) async throws -> DigitalCertificateResponse {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw ServiceError.badResponse("Geçersiz VIN.")
        }
        guard phonePublicKey.range(of: "^[0-9a-fA-F]{128}$", options: .regularExpression) != nil else {
            throw ServiceError.badResponse("Telefon açık anahtarı geçersiz.")
        }

        let path = "/smart-access/api/v1/Certificates/GetCertificate?phonePublicKey=\(phonePublicKey)&vin=\(vin)&isOwner=true"
        let json = try await get(
            path,
            extraHeaders: [
                "x-app-build-number": "663",
                "Accept": "application/json"
            ]
        )

        let certificateKeys = ["certificateBase64", "certificate", "cert"]
        guard let certificate = certificateKeys
            .compactMap({ json[$0] as? String })
            .first(where: { !$0.isEmpty }) else {
            throw ServiceError.badResponse("Sunucu doğrulanabilir dijital anahtar sertifikası döndürmedi.")
        }

        let vehicleKey = ["carPublicKey", "vehiclePublicKey", "vehicleKey", "smartAccessCarPubKey"]
            .compactMap { json[$0] as? String }
            .first(where: { !$0.isEmpty })

        AppLog.info(.network, "Dijital anahtar sertifikası alındı; araç anahtarı=\(vehicleKey == nil ? "yanıtta yok" : "var")")
        return DigitalCertificateResponse(
            certificateBase64: certificate,
            vehiclePublicKey: vehicleKey
        )
    }

    func climateState(vin: String) async throws -> ClimateState {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw ServiceError.badResponse("Geçersiz VIN.")
        }

        let payload = Self.protoString(field: 1, value: vin)
        let response = try await grpcCall(
            method: "GetClimateControlStatus",
            payload: payload,
            timeout: "30000m"
        )
        guard let outer = Self.protoBytesField(response, field: 1),
              let inner = Self.protoBytesField(outer, field: 1) else {
            throw ServiceError.badResponse("Klima durumu beklenen formatta değil.")
        }

        let active = Self.protoVarintField(inner, field: 1) == 1
        var temperature: Double?
        if let hvac = Self.protoBytesField(inner, field: 2),
           let raw = Self.protoFloatField(hvac, field: 1),
           raw.isFinite {
            temperature = Double(raw)
        }
        return ClimateState(active: active, temperature: temperature)
    }

    func sendClimateCommand(
        vin: String,
        enabled: Bool,
        temperature: Double
    ) async throws -> ClimateCommandResult {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw ServiceError.badResponse("Geçersiz VIN.")
        }
        guard temperature.isFinite, (16...30).contains(temperature) else {
            throw ServiceError.badResponse("Hedef sıcaklık 16–30°C arasında olmalı.")
        }

        let hvac = Self.protoHVAC(enabled: enabled, temperature: enabled ? Float(temperature) : nil)
        let payload = Self.protoString(field: 1, value: vin) + Self.protoBytes(field: 2, value: hvac)
        let response = try await grpcCall(
            method: "SendClimateControlCommand",
            payload: payload,
            timeout: "240000m"
        )

        let replies = Self.grpcFrames(response).compactMap { Self.protoCommandResult($0) }
        guard let reply = replies.last else {
            throw ServiceError.badResponse("Klima komutu yanıtı beklenen formatta değil.")
        }
        try ClimateCommandError.check(reply)
        return reply
    }

    private func grpcCall(method: String, payload: Data, timeout: String) async throws -> Data {
        var request = URLRequest(
            url: URL(string: "https://tva-api.togg.cloud:9443/tr.com.togg.tva.remotecontrol.gRpcRemoteControlService/\\(method)")!
        )
        request.httpMethod = "POST"
        request.httpBody = Self.grpcFrame(payload)
        request.setValue("Bearer \\(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
        request.setValue("trailers", forHTTPHeaderField: "TE")
        request.setValue(timeout, forHTTPHeaderField: "grpc-timeout")
        request.setValue("identity", forHTTPHeaderField: "grpc-accept-encoding")
        request.setValue("ios-garajim/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ServiceError.http(status)
        }
        guard !data.isEmpty else {
            throw ServiceError.badResponse("Klima servisi boş yanıt verdi.")
        }
        return data
    }

    private static func protoVarint(_ value: Int) -> Data {
        var value = UInt64(value)
        var result = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            result.append(byte)
        } while value != 0
        return result
    }

    private static func protoBytes(field: Int, value: Data) -> Data {
        protoVarint((field << 3) | 2) + protoVarint(value.count) + value
    }

    private static func protoString(field: Int, value: String) -> Data {
        protoBytes(field: field, value: Data(value.utf8))
    }

    private static func protoHVAC(enabled: Bool, temperature: Float?) -> Data {
        var result = Data()
        if enabled {
            result.append(0x08)
            result.append(0x01)
        }
        if let temperature {
            result.append(0x15)
            var value = temperature.bitPattern.littleEndian
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
        return result
    }

    private static func grpcFrame(_ payload: Data) -> Data {
        var result = Data([0])
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }

    private static func grpcFrames(_ data: Data) -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset + 5 <= data.count {
            guard data[offset] == 0 else { break }
            let length = Int(data[offset + 1]) << 24
                | Int(data[offset + 2]) << 16
                | Int(data[offset + 3]) << 8
                | Int(data[offset + 4])
            offset += 5
            guard length >= 0, length <= 1_048_576, offset + length <= data.count else { break }
            result.append(data.subdata(in: offset..<(offset + length)))
            offset += length
        }
        return result
    }

    private static func protoFields(_ data: Data) -> [(field: Int, wire: Int, value: Data)] {
        var fields: [(Int, Int, Data)] = []
        var index = 0

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < data.count else { return nil }
                let byte = data[index]
                index += 1
                result |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 { return result }
            }
            return nil
        }

        while index < data.count {
            guard let tag = readVarint() else { break }
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x07)
            guard field > 0 else { break }

            switch wire {
            case 0:
                guard let value = readVarint() else { return fields }
                var encoded = Data()
                var mutable = value
                repeat {
                    var byte = UInt8(mutable & 0x7F)
                    mutable >>= 7
                    if mutable != 0 { byte |= 0x80 }
                    encoded.append(byte)
                } while mutable != 0
                fields.append((field, wire, encoded))
            case 2:
                guard let length = readVarint(), length <= 1_048_576 else { return fields }
                let end = index + Int(length)
                guard end <= data.count else { return fields }
                fields.append((field, wire, data.subdata(in: index..<end)))
                index = end
            case 5:
                guard index + 4 <= data.count else { return fields }
                fields.append((field, wire, data.subdata(in: index..<(index + 4))))
                index += 4
            default:
                return fields
            }
        }
        return fields
    }

    private static func protoBytesField(_ data: Data, field: Int) -> Data? {
        protoFields(data).last { $0.field == field && $0.wire == 2 }?.value
    }

    private static func protoVarintField(_ data: Data, field: Int) -> UInt64? {
        guard let raw = protoFields(data).last(where: { $0.field == field && $0.wire == 0 })?.value else {
            return nil
        }
        return raw.enumerated().reduce(UInt64(0)) { result, item in
            result | (UInt64(item.element & 0x7F) << UInt64(item.offset * 7))
        }
    }

    private static func protoFloatField(_ data: Data, field: Int) -> Float? {
        guard let raw = protoFields(data).last(where: { $0.field == field && $0.wire == 5 })?.value,
              raw.count == 4 else { return nil }
        return raw.withUnsafeBytes { Float(bitPattern: UInt32(littleEndian: $0.load(as: UInt32.self))) }
    }

    private static func protoStringField(_ data: Data, field: Int) -> String? {
        guard let raw = protoBytesField(data, field: field) else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    private static func protoCommandResult(_ data: Data) -> ClimateCommandResult? {
        guard let status = protoStringField(data, field: 2), !status.isEmpty else { return nil }
        return ClimateCommandResult(
            requestID: protoStringField(data, field: 1),
            status: status,
            code: protoStringField(data, field: 3)
        )
    }

    func accountNotifications() async throws -> [LiveNotification] {
        let json = try await get(
            "/integration/api/v1/Notifications/all",
            base: "https://superapp-api.channels.togg.cloud",
            extraHeaders: ["x-app-build-number": "663", "Accept": "application/json"]
        )
        return AccountPayload.items(json, preferredKeys: ["notifications", "notificationList"]).enumerated().map { index, item in
            LiveNotification(
                id: AccountPayload.text(item, "id", "notificationId", "uuid") ?? "notification-\\(index)",
                title: AccountPayload.text(item, "title", "subject", "name") ?? "Bildirim",
                detail: AccountPayload.text(item, "message", "description", "body", "content") ?? "",
                date: AccountPayload.date(item, "createdAt", "createdOn", "date", "timestamp"),
                symbol: AccountPayload.text(item, "icon", "symbol") ?? "bell.fill"
            )
        }
    }

    func serviceRecords() async throws -> [LiveServiceRecord] {
        let json = try await get(
            "/integration/api/v1/Tickets/Tur",
            base: "https://superapp-api.channels.togg.cloud",
            extraHeaders: ["x-app-build-number": "663", "Accept": "application/json"]
        )
        return AccountPayload.items(json, preferredKeys: ["tickets", "services", "records"]).enumerated().map { index, item in
            LiveServiceRecord(
                id: AccountPayload.text(item, "ticketId", "id", "number") ?? "service-\\(index)",
                title: AccountPayload.text(item, "title", "subject", "type", "description") ?? "Servis kaydı",
                place: AccountPayload.text(item, "dealerName", "serviceName", "location", "place") ?? "Servis",
                date: AccountPayload.date(item, "createdAt", "createdOn", "date", "appointmentDate"),
                status: AccountPayload.text(item, "status", "state", "ticketStatus")
            )
        }
    }

    func subscriptions() async throws -> [LiveSubscription] {
        let json = try await get(
            "/integration/api/v1/Package/Tur/subscriptions",
            base: "https://superapp-api.channels.togg.cloud",
            extraHeaders: ["x-app-build-number": "663", "Accept": "application/json"]
        )
        return AccountPayload.items(json, preferredKeys: ["subscriptions", "packages", "plans"]).enumerated().map { index, item in
            let active = AccountPayload.bool(item, "isActive", "active", "enabled", "isSubscribed")
                ?? (AccountPayload.text(item, "status", "state")?.lowercased() == "active")
            return LiveSubscription(
                id: AccountPayload.text(item, "id", "subscriptionId", "code") ?? "subscription-\\(index)",
                title: AccountPayload.text(item, "name", "title", "packageName", "productName") ?? "Abonelik",
                detail: AccountPayload.text(item, "description", "detail", "planName", "renewalDate") ?? "",
                isActive: active
            )
        }
    }

    /// Henüz arayüzde kullanılmayan salt okunur uç noktaların yanıt yapısını günlüğe yazar.
    /// Şema doğrulanmadığından yalnızca hata ayıklama derlemesinde çalışır; yanıt değerleri yazılmaz,
    /// yalnızca anahtar yapısı yazılır.
    func probeExtraEndpoints(for vehicle: VehicleSummary) async {
        #if DEBUG
        let vin = vehicle.vin
        let tva = "/info/api/v1/DriveExperience/\(vin)"
        let superApp = "https://superapp-api.channels.togg.cloud"
        let appHeaders = ["x-app-build-number": "663", "Accept": "application/json"]
        let probes: [(String, String, String?)] = [
            ("özet", tva + "/insightsDashboard", nil),
            ("sürüşler", tva + "/journeysOverviewMonthly?limit=20&offset=0", nil),
            ("şarjlar", tva + "/chargingOverviewMonthly?limit=20&offset=0", nil),
            ("bildirimler", "/integration/api/v1/Notifications/all", superApp),
            ("servis", "/integration/api/v1/Tickets/Tur", superApp),
            ("abonelikler", "/integration/api/v1/Package/Tur/subscriptions", superApp),
        ]
        for (name, path, base) in probes {
            do {
                let json = try await get(path, base: base, extraHeaders: base == nil ? [:] : appHeaders)
                AppLog.info(.parse, "Keşif · \(name): \(AppLog.shape(json))")
            } catch {
                AppLog.warning(.parse, "Keşif · \(name) alınamadı: \(AppLog.describe(error))")
            }
        }
        #endif
    }

    /// Birim ve biçim tespiti için ham değerleri yazar. Konum ve VIN içermez.
    private static func logRawValues(json: [String: Any], telemetry t: [String: Any]) {
        // Ham sürüş ve telemetri verisi kişiseldir; yalnızca hata ayıklama derlemesinde yazılır.
        #if DEBUG
        var picked: [String: Any] = [:]
        for key in ["color", "dataVolume", "dateFormat", "lastTripInfo", "year", "model", "manufacture", "versionInfo"] {
            if let value = json[key] { picked[key] = value }
        }
        for key in ["obcState", "driveMode", "vehicleStatus", "odometerStatus", "vehicleRange", "battery", "tirePressure",
                    "tireTemperature", "breakWarning", "engineWarning"] {
            if let value = t[key] { picked["telemetry." + key] = value }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: picked, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        AppLog.debug(.parse, "Ham değerler (konum/VIN hariç): \(text.prefix(8000))")
        #endif
    }

    /// Yanıttaki tüm anahtar yollarını ve değer türlerini yazar; değerleri YAZMAZ.
    /// Amaç, uygulamanın henüz okumadığı alanları (kapı/cam durumu, şarj gücü vb.) keşfetmektir.
    /// Dizilerde yalnızca ilk öğe incelenir. Yol sayısı ve derinlik sınırlıdır.
    private static func logResponseShape(json: [String: Any]) {
        #if DEBUG
        var paths: [String] = []
        func kind(_ value: Any) -> String {
            if let number = value as? NSNumber {
                return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "sayı"
            }
            if value is String { return "metin" }
            if value is NSNull { return "null" }
            return "?"
        }
        func walk(_ value: Any, _ path: String, _ depth: Int) {
            guard paths.count < 400 else { return }
            if let dict = value as? [String: Any] {
                if dict.isEmpty { paths.append("\(path): {}"); return }
                guard depth < 6 else { paths.append("\(path): {…}"); return }
                for key in dict.keys.sorted() { walk(dict[key] as Any, path.isEmpty ? key : "\(path).\(key)", depth + 1) }
            } else if let array = value as? [Any] {
                if let first = array.first, depth < 6 {
                    walk(first, "\(path)[]", depth + 1)
                } else {
                    paths.append("\(path)[]: boş")
                }
            } else {
                paths.append("\(path): \(kind(value))")
            }
        }
        walk(json, "", 0)
        AppLog.debug(.parse, "Yanıt şeması (\(paths.count) yol, değer yok): \(paths.joined(separator: " | ").prefix(12000))")
        #endif
    }

    /// Hangi alanların okunabildiğini yazar. Konum için yalnızca var/yok bilgisi verilir.
    private static func logFieldSummary(_ state: VehicleState) {
        func f(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "yok" }
        let located = state.latitude != nil && state.longitude != nil
        let checks: [(String, Bool)] = [
            ("battery", state.battery != nil), ("range", state.range != nil),
            ("odometer", state.odometer != nil), ("inside", state.inside != nil),
            ("outside", state.outside != nil), ("auxBattery", state.auxBattery != nil),
            ("konum", located),
            ("tireFL", state.tiresFrontPSI.0 != nil), ("tireFR", state.tiresFrontPSI.1 != nil),
            ("tireRL", state.tiresRearPSI.0 != nil), ("tireRR", state.tiresRearPSI.1 != nil),
            ("updatedOn", state.updatedOn != nil),
        ]
        let missing = checks.filter { !$0.1 }.map(\.0)
        AppLog.info(.parse, "Alan özeti: \(checks.count - missing.count)/\(checks.count) okundu, eksik=\(missing.isEmpty ? "yok" : missing.joined(separator: ","))")
        AppLog.debug(.parse, "Değerler: battery=\(f(state.battery))%, range=\(f(state.range)) km, odometer=\(f(state.odometer)) km, inside=\(f(state.inside))°, outside=\(f(state.outside))°, aux=\(f(state.auxBattery))%, lastik PSI=[\(f(state.tiresFrontPSI.0)), \(f(state.tiresFrontPSI.1)), \(f(state.tiresRearPSI.0)), \(f(state.tiresRearPSI.1))], konum=\(located ? "var" : "yok"), lastik °C=[\(f(state.tireTempsFrontC.0)), \(f(state.tireTempsFrontC.1)), \(f(state.tireTempsRearC.0)), \(f(state.tireTempsRearC.1))], fren uyarısı=\(state.brakeWarning.map(String.init(describing:)) ?? "yok"), sistem uyarısı=\(state.engineWarning.map(String.init(describing:)) ?? "yok"), sürüm=\(state.softwareVersion ?? "yok"), ort. hız=\(f(state.currentTrip?.averageSpeedKmh))/\(f(state.lastChargeTrip?.averageSpeedKmh)) km/sa")
    }

    // MARK: Yardımcılar

    private static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    nonisolated var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
