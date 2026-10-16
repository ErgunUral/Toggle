import SwiftUI
import AuthenticationServices
import CoreLocation
import WidgetKit

/// Uygulamanın tek veri kaynağı. Giriş yapılmamışsa örnek veri,
/// yapılmışsa Togg'dan canlı veri ve desteklenen uzaktan kontrolleri kullanır.
@MainActor @Observable
final class GarageStore {
    private static let colorKey = "vehicleColor"
    /// Ayarlar'daki klima açılış derecesinin `UserDefaults` anahtarı.
    static let climateDefaultKey = "climateDefaultTemp"
    static let climateTemperatureRange = 16...30

    var snapshot = VehicleSnapshot()
    /// Araçtan okunan son renk; henüz okunmadıysa son kaydedilen ya da mavi.
    var color: VehicleColor
    var isRefreshing = false
    var isSignedIn = false
    var message: String?
    var vehicles: [VehicleSummary] = []
    var selectedVIN: String?

    let history = HistoryStore()

    private let service = TogglService.shared
    private var didProbeExtraEndpoints = false

    init() {
        let defaults = UserDefaults.standard
        color = VehicleColor(rawValue: defaults.string(forKey: Self.colorKey) ?? "") ?? .blue
        // Elle renk seçimi kaldırıldı; eski ayar kalmasın.
        defaults.removeObject(forKey: "vehicleColorIsManual")
        snapshot.targetTemperature = Self.climateDefaultTemperature
    }

    /// Kayıtlı klima açılış derecesi; yoksa ya da aralık dışındaysa 22 °C.
    static var climateDefaultTemperature: Int {
        let stored = UserDefaults.standard.integer(forKey: climateDefaultKey)
        return climateTemperatureRange.contains(stored) ? stored : 22
    }

    // MARK: Renk

    private func setColor(_ newColor: VehicleColor) {
        color = newColor
        UserDefaults.standard.set(newColor.rawValue, forKey: Self.colorKey)
    }

    // MARK: Oturum

    /// Keychain'deki oturumu okur; oturum varsa canlı veriyi yükler.
    func syncSignInState() async {
        isSignedIn = await service.isSignedIn
        AppLog.info(.app, "Oturum durumu: \(isSignedIn ? "açık (canlı mod)" : "kapalı (örnek mod)")")
        if isSignedIn { await refresh() }
    }

    func signIn(using session: WebAuthenticationSession) async {
        AppLog.info(.auth, "Giriş akışı başlatıldı")
        message = nil
        let login = await service.prepareLogin()
        do {
            let callback = try await session.authenticate(using: login.url, callbackURLScheme: "superapp")
            try await service.completeLogin(callback: callback, state: login.state, verifier: login.verifier)
            isSignedIn = true
            AppLog.info(.auth, "Giriş başarılı; canlı veri yükleniyor")
            await refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            AppLog.warning(.auth, "Giriş kullanıcı tarafından iptal edildi")
            message = ServiceError.cancelled.localizedDescription
        } catch {
            AppLog.error(.auth, "Giriş başarısız: \(AppLog.describe(error))")
            message = error.localizedDescription
        }
    }

    func signOut() async {
        AppLog.info(.auth, "Çıkış yapılıyor; örnek moda dönülüyor")
        await service.signOut()
        isSignedIn = false
        vehicles = []
        selectedVIN = nil
        snapshot = VehicleSnapshot()
        // Başka hesapla girilirse eski aracın ölçümleri yeni grafiklere karışmasın.
        history.clear()
        message = nil
    }

    // MARK: Veri

    /// Başka araca geçilince eski aracın ölçümleri yeni aracın grafiklerine karışmasın.
    func selectVehicle(_ vin: String) async {
        guard vin != selectedVIN else { return }
        selectedVIN = vin
        history.clear()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else {
            AppLog.debug(.refresh, "Yenileme atlandı: zaten sürüyor")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard isSignedIn else {
            // Örnek modda yalnızca "güncellendi" zamanını yeniler.
            AppLog.debug(.refresh, "Örnek mod yenilemesi")
            try? await Task.sleep(for: .milliseconds(900))
            snapshot.updatedAt = .now
            return
        }

        let started = ContinuousClock.now
        AppLog.info(.refresh, "Canlı yenileme başladı")
        do {
            vehicles = try await service.vehicles()
            if selectedVIN == nil || !vehicles.contains(where: { $0.vin == selectedVIN }) {
                selectedVIN = vehicles.first?.vin
                AppLog.info(.refresh, "Araç seçildi: \(selectedVIN.map(AppLog.maskVIN) ?? "yok") (toplam \(vehicles.count))")
            }
            guard let vehicle = vehicles.first(where: { $0.vin == selectedVIN }) else {
                AppLog.warning(.refresh, "Hesapta araç bulunamadı")
                message = "Hesabında araç bulunamadı."
                return
            }
            apply(try await service.state(for: vehicle))
            snapshot.plate = vehicle.plate.isEmpty ? nil : vehicle.plate
            // Model yılı için liste doğru; VehicleInfo'daki yıl yanlış geliyor.
            if let year = vehicle.year.flatMap({ Int($0) }) { snapshot.year = year }
            snapshot.ownerType = vehicle.ownerType
            snapshot.keySharingEnabled = vehicle.keySharingEnabled
            snapshot.manufacturer = vehicle.manufacturer
            history.record(snapshot)
            // Yeni uç noktaların yanıt yapısını oturum başına bir kez günlüğe yazar (yalnızca DEBUG'da etkindir).
            if !didProbeExtraEndpoints {
                didProbeExtraEndpoints = true
                await service.probeExtraEndpoints(for: vehicle)
            }
            message = nil
            AppLog.info(.refresh, "Canlı yenileme tamamlandı (\(AppLog.ms(since: started)))")
        } catch ServiceError.sessionExpired {
            AppLog.warning(.refresh, "Oturum süresi doldu (\(AppLog.ms(since: started))); çıkış yapılıyor")
            await signOut()
            message = ServiceError.sessionExpired.localizedDescription
        } catch {
            AppLog.error(.refresh, "Canlı yenileme başarısız (\(AppLog.ms(since: started))): \(AppLog.describe(error))")
            message = error.localizedDescription
        }
    }

    /// Canlı veriyi okunabilen alanlara yazar. Okunamayan alanlar nil kalır;
    /// internet kotası ve kontroller için canlı kaynak olmadığından örnek kalır.
    private func apply(_ live: VehicleState) {
        var next = VehicleSnapshot()
        next.isLive = true
        next.name = live.name
        next.model = Self.modelName(live.model)
        next.edition = live.edition
        next.vin = AppLog.maskVIN(live.vin)
        next.battery = live.battery.map { $0 / 100 }
        next.range = live.range
        next.batteryEnergyKWh = live.batteryEnergyKWh
        next.odometer = live.odometer
        next.inside = live.inside
        next.outside = live.outside
        next.auxBattery = live.auxBattery.map { $0 / 100 }
        if let quota = live.internetQuota {
            next.internetUsedGB = quota.usedGB
            next.internetQuotaGB = quota.totalGB
            next.internetQuotaIsLive = true
        }
        next.tires = TirePressure(
            frontLeft: live.tiresFrontPSI.0,
            frontRight: live.tiresFrontPSI.1,
            rearLeft: live.tiresRearPSI.0,
            rearRight: live.tiresRearPSI.1
        )
        next.tireTemperatures = TireTemperatures(
            frontLeft: live.tireTempsFrontC.0,
            frontRight: live.tireTempsFrontC.1,
            rearLeft: live.tireTempsRearC.0,
            rearRight: live.tireTempsRearC.1
        )
        next.brakeWarning = live.brakeWarning
        next.engineWarning = live.engineWarning
        next.softwareVersion = live.softwareVersion
        if let latitude = live.latitude, let longitude = live.longitude {
            next.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            next.coordinate = nil
        }
        next.address = nil
        next.updatedAt = live.updatedOn

        // Kalan enerji / doluluk = kullanılabilir kapasite. Farklı doluluklarda aynı kalmalıdır;
        // kalmıyorsa `batteryTotalEnergyValue` kalan enerji değil kapasitedir.
        let capacity = next.usableCapacityKWh

        if let trip = live.currentTrip, let sinceCharge = live.lastChargeTrip {
            next.currentTrip = Self.stats(from: trip, title: "Güncel sürüş")
            next.sinceCharge = Self.stats(from: sinceCharge, title: "Son şarjdan beri")
            next.tripsAreLive = true
        }
        next.isCharging = live.isCharging
        next.driveMode = live.driveMode.map(Self.driveModeText)
        func format(_ value: Double?, _ spec: String) -> String {
            value.map { String(format: spec, $0) } ?? "yok"
        }
        let energyText = "kalan=\(format(live.batteryEnergyKWh, "%.2f")) kWh, doluluk=\(format(live.battery, "%.0f"))%"
        let rangeText = "araç menzili=\(format(live.range, "%.0f")) km, gerçekçi menzil=\(format(next.realisticRange, "%.0f")) km"
        AppLog.info(.parse, "Enerji: \(energyText) → ima edilen kapasite=\(format(capacity, "%.1f")) kWh, \(rangeText) (tüketim=\(format(next.sinceCharge.average, "%.1f")) kWh/100 km)")
        snapshot = next
        publishWidgetSnapshot(next)

        applyVehicleColor(named: live.colorName)
        AppLog.debug(.refresh, "Anlık görüntü canlı veriyle güncellendi (sürüş özeti canlı=\(next.tripsAreLive), şarj oluyor=\(next.isCharging.map(String.init(describing:)) ?? "bilinmiyor"))")
    }

    private func publishWidgetSnapshot(_ snapshot: VehicleSnapshot) {
        guard let defaults = UserDefaults(suiteName: "group.com.ibrahim.togggaraj") else { return }
        defaults.set(snapshot.name, forKey: "widget.vehicleName")
        defaults.set(Int((snapshot.battery ?? 0) * 100), forKey: "widget.batteryPercent")
        defaults.set(Int(snapshot.range ?? 0), forKey: "widget.rangeKm")
        defaults.set(snapshot.isLive, forKey: "widget.isLive")
        WidgetCenter.shared.reloadTimelines(ofKind: "GarageWidget")
    }

    /// Araçtan gelen rengi okur ve uygular; okunamayan ya da tanınmayan renkte son renk korunur.
    private func applyVehicleColor(named name: String?) {
        guard let name else {
            AppLog.debug(.parse, "Araç rengi: yanıtta yok")
            return
        }
        guard let parsed = VehicleColor(apiName: name) else {
            AppLog.warning(.parse, "Araç rengi tanınmadı: '\(name)' (bilinen renkler: \(VehicleColor.allCases.map(\.rawValue).joined(separator: ",")))")
            return
        }
        if parsed != color {
            AppLog.info(.parse, "Araç rengi uygulandı: \(color.rawValue) → \(parsed.rawValue)")
            setColor(parsed)
        }
    }

    /// Aracın bildirdiği sürüş özeti. Enerji ve batarya yüzdesi tahmini hesaplanmaz, nil kalır.
    private static func stats(from trip: TripInfo, title: String) -> TripStats {
        var parts: [String] = []
        // Servisin `updatedOn` değeri her çekimde "şimdi" geldiğinden sürüş zamanı olarak gösterilmez.
        if let minutes = trip.durationMinutes { parts.append("\(minutes / 60) sa \(minutes % 60) dk") }
        return TripStats(
            distance: trip.distanceKm,
            average: trip.averageConsumption,
            energy: nil,
            batteryPercent: nil,
            note: parts.isEmpty ? title : parts.joined(separator: " · "),
            averageSpeed: trip.averageSpeedKmh
        )
    }

    /// Togg'un dahili model kodu CSUV, pazarlama adı T10X'tir.
    static func modelName(_ code: String) -> String {
        code.uppercased() == "CSUV" ? "T10X" : code
    }

    /// DRIVEMODE_COMFORT → Comfort
    private static func driveModeText(_ mode: String) -> String {
        mode.replacingOccurrences(of: "DRIVEMODE_", with: "").capitalized
    }

    // MARK: Yerel ve canlı kontroller

    // MARK: Sunucu analizleri

    /// Seçili aracın Togg sunucusundaki özet blokları. Oturum ya da araç yoksa boş döner.
    func serverInsights() async throws -> [ServerInsightBlock] {
        guard isSignedIn, let vin = selectedVIN else { return [] }
        return try await service.insights(vin: vin)
    }

    func serverRecords(isCharge: Bool, period: AnalyticsPeriod, offset: Int) async throws -> ServerRecordPage {
        guard isSignedIn, let vin = selectedVIN else {
            return ServerRecordPage(records: [], totals: ServerMetrics([:]), hasMore: false)
        }
        return try await service.records(vin: vin, isCharge: isCharge, period: period, offset: offset)
    }

    func climateState() async throws -> ClimateState {
        guard isSignedIn, let vin = selectedVIN else { throw ServiceError.notSignedIn }
        return try await service.climateState(vin: vin)
    }

    func sendClimateCommand(enabled: Bool, temperature: Double) async throws -> ClimateCommandResult {
        guard isSignedIn, let vin = selectedVIN else { throw ServiceError.notSignedIn }
        return try await service.sendClimateCommand(vin: vin, enabled: enabled, temperature: temperature)
    }

    func accountNotifications() async throws -> [LiveNotification] {
        guard isSignedIn else { return [] }
        return try await service.accountNotifications()
    }

    func serviceRecords() async throws -> [LiveServiceRecord] {
        guard isSignedIn else { return [] }
        return try await service.serviceRecords()
    }

    func subscriptions() async throws -> [LiveSubscription] {
        guard isSignedIn else { return [] }
        return try await service.subscriptions()
    }

    func toggleLock() { snapshot.doorsLocked.toggle() }
    func toggleTrunk() { snapshot.trunkOpen.toggle() }
    func toggleClimate() {
        snapshot.climateOn.toggle()
        // Klima açılırken Ayarlar'daki açılış derecesi kullanılır.
        if snapshot.climateOn { snapshot.targetTemperature = Self.climateDefaultTemperature }
    }

    func adjustTemperature(by delta: Int) {
        let range = Self.climateTemperatureRange
        snapshot.targetTemperature = min(range.upperBound, max(range.lowerBound, snapshot.targetTemperature + delta))
    }
}
