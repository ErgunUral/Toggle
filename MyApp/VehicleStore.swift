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
    var id: String { vin }
}

/// VehicleInfo yanıtındaki bir sürüş özeti. Mesafe metreden kilometreye çevrilmiş halde tutulur.
nonisolated struct TripInfo: Sendable {
    var distanceKm: Double
    var averageConsumption: Double?
    var durationMinutes: Int?
    var updatedOn: Date?
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
    var latitude: Double?
    var longitude: Double?
    var updatedOn: Date?
    var tiresFrontPSI: (Double?, Double?) = (nil, nil)
    var tiresRearPSI: (Double?, Double?) = (nil, nil)
    var currentTrip: TripInfo?
    var lastChargeTrip: TripInfo?
    /// `batteryTotalEnergyValue`. Değerin anlamı kesin değil: %72 doluluktayken 60,16 geldi;
    /// 60,16 / 0,72 ≈ 83,6 kWh (T10X'in kullanılabilir kapasitesine yakın) olduğundan
    /// kalan enerji (kWh) olarak yorumlanır.
    var batteryEnergyKWh: Double?
    /// Araç rengi, API'deki adıyla (örn. "BLUE").
    var colorName: String?
    var chargeMode: String?
    var driveMode: String?
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
        guard let range = path.range(of: "vin=") else { return path }
        let vin = String(path[range.upperBound...].prefix(17))
        return path.replacingOccurrences(of: vin, with: AppLog.maskVIN(vin))
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let label = Self.redact(path)
        var request = URLRequest(url: URL(string: apiBase + path)!)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("TR", forHTTPHeaderField: "language")

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
                    edition: dict["edition"] as? String ?? ""
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
                durationMinutes: Int(minutes),
                updatedOn: parseDate(dict["updatedOn"] as? String)
            )
        }
        state.currentTrip = trip("currentTrip")
        state.lastChargeTrip = trip("lastChargeTrip")
        state.batteryEnergyKWh = num(at(t, "battery", "content", "batteryTotalEnergy", "batteryTotalEnergyValue"))
        state.colorName = json["color"] as? String
        state.chargeMode = at(t, "obcState", "content", "chargeMode", "chargeModeEnumValue") as? String
        state.driveMode = at(t, "driveMode", "content", "driveModeState", "driveMode") as? String
        AppLog.debug(.parse, "Sürüş özetleri: güncel=\(state.currentTrip == nil ? "yok" : "var"), sonŞarj=\(state.lastChargeTrip == nil ? "yok" : "var"); şarj modu=\(state.chargeMode ?? "yok"); sürüş modu=\(state.driveMode ?? "yok"); batarya enerjisi=\(state.batteryEnergyKWh.map { String(format: "%.2f kWh", $0) } ?? "yok") (ham), renk=\(state.colorName ?? "yok")")
        Self.logFieldSummary(state)
        Self.logRawValues(json: json, telemetry: t)
        return state
    }

    /// Birim ve biçim tespiti için ham değerleri yazar. Konum ve VIN içermez.
    private static func logRawValues(json: [String: Any], telemetry t: [String: Any]) {
        // Ham sürüş ve telemetri verisi kişiseldir; yalnızca hata ayıklama derlemesinde yazılır.
        #if DEBUG
        var picked: [String: Any] = [:]
        for key in ["color", "dataVolume", "dateFormat", "lastTripInfo", "year", "model"] {
            if let value = json[key] { picked[key] = value }
        }
        for key in ["obcState", "driveMode", "vehicleStatus", "odometerStatus", "vehicleRange", "battery", "tirePressure"] {
            if let value = t[key] { picked["telemetry." + key] = value }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: picked, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        AppLog.debug(.parse, "Ham değerler (konum/VIN hariç): \(text.prefix(3500))")
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
        AppLog.debug(.parse, "Değerler: battery=\(f(state.battery))%, range=\(f(state.range)) km, odometer=\(f(state.odometer)) km, inside=\(f(state.inside))°, outside=\(f(state.outside))°, aux=\(f(state.auxBattery))%, lastik PSI=[\(f(state.tiresFrontPSI.0)), \(f(state.tiresFrontPSI.1)), \(f(state.tiresRearPSI.0)), \(f(state.tiresRearPSI.1))], konum=\(located ? "var" : "yok")")
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
