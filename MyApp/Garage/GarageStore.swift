import SwiftUI
import AuthenticationServices
import CoreLocation

/// Uygulamanın tek veri kaynağı. Giriş yapılmamışsa örnek veri, yapılmışsa
/// Togg'dan salt okunur canlı veri gösterir. Araca komut göndermez.
@MainActor @Observable
final class GarageStore {
    private static let colorKey = "vehicleColor"

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

    init() {
        let defaults = UserDefaults.standard
        color = VehicleColor(rawValue: defaults.string(forKey: Self.colorKey) ?? "") ?? .blue
        // Elle renk seçimi kaldırıldı; eski ayar kalmasın.
        defaults.removeObject(forKey: "vehicleColorIsManual")
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
            history.record(snapshot)
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
        next.model = live.model
        next.edition = live.edition
        next.vin = AppLog.maskVIN(live.vin)
        next.battery = live.battery.map { $0 / 100 }
        next.range = live.range
        next.batteryEnergyKWh = live.batteryEnergyKWh
        next.odometer = live.odometer
        next.inside = live.inside
        next.outside = live.outside
        next.auxBattery = live.auxBattery.map { $0 / 100 }
        next.tires = TirePressure(
            frontLeft: live.tiresFrontPSI.0,
            frontRight: live.tiresFrontPSI.1,
            rearLeft: live.tiresRearPSI.0,
            rearRight: live.tiresRearPSI.1
        )
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
            next.currentTrip = Self.stats(from: trip, capacityKWh: capacity, title: "Güncel sürüş")
            next.sinceCharge = Self.stats(from: sinceCharge, capacityKWh: capacity, title: "Son şarjdan beri")
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

        applyVehicleColor(named: live.colorName)
        AppLog.debug(.refresh, "Anlık görüntü canlı veriyle güncellendi (sürüş özeti canlı=\(next.tripsAreLive), şarj oluyor=\(next.isCharging.map(String.init(describing:)) ?? "bilinmiyor"))")
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

    /// Enerji ve batarya tüketimi, ortalama tüketimden ve kullanılabilir kapasiteden tahmin edilir.
    private static func stats(from trip: TripInfo, capacityKWh: Double?, title: String) -> TripStats {
        let energy = trip.averageConsumption.map { trip.distanceKm * $0 / 100 }
        let percent = energy.flatMap { energy in capacityKWh.flatMap { $0 > 0 ? energy / $0 * 100 : nil } }
        var parts: [String] = []
        if let minutes = trip.durationMinutes { parts.append("\(minutes / 60) sa \(minutes % 60) dk") }
        if let updatedOn = trip.updatedOn { parts.append(updatedOn.shortDateTimeText) }
        return TripStats(
            distance: trip.distanceKm,
            average: trip.averageConsumption,
            energy: energy,
            batteryPercent: percent,
            note: parts.isEmpty ? title : parts.joined(separator: " · ")
        )
    }

    /// DRIVEMODE_COMFORT → Comfort
    private static func driveModeText(_ mode: String) -> String {
        mode.replacingOccurrences(of: "DRIVEMODE_", with: "").capitalized
    }

    // MARK: Örnek kontroller (canlı modda kapalıdır; araca komut göndermez)

    func toggleLock() { snapshot.doorsLocked.toggle() }
    func toggleTrunk() { snapshot.trunkOpen.toggle() }
    func toggleClimate() { snapshot.climateOn.toggle() }

    func adjustTemperature(by delta: Int) {
        snapshot.targetTemperature = min(30, max(16, snapshot.targetTemperature + delta))
    }
}
