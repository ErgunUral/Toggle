import CoreBluetooth
import CryptoKit
import Foundation
import Observation
import UserNotifications

/// Protokol şeması doğrulanana kadar yalnızca yerel olarak hazırlanan imzalı çerçeve.
enum BLEGarageError: LocalizedError {
    case notConnected
    case invalidAcknowledgement
    case invalidVehicleClock
    case certificateRequired
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Araç Bluetooth bağlantısı hazır değil."
        case .invalidAcknowledgement:
            "Araç komutu kabul ettiğini doğrulayan ACK paketi göndermedi."
        case .invalidVehicleClock:
            "Araç saati geçersiz."
        case .certificateRequired:
            "Araç sertifikası ve doğrulama anahtarı hazır değil."
        case .timeout:
            "Araç Bluetooth yanıtı zaman aşımına uğradı."
        }
    }
}

struct SignedBLEFrame: Sendable {
    let timestampMilliseconds: UInt64
    let nonce: Data
    let commandPayload: Data
    let signature: Data

    /// İmzalanan canonical byte dizisi. Araç protokolünün wire formatı değildir.
    var signedBytes: Data {
        var bytes = Data()
        var timestamp = timestampMilliseconds.bigEndian
        withUnsafeBytes(of: &timestamp) { bytes.append(contentsOf: $0) }
        bytes.append(nonce)
        bytes.append(commandPayload)
        return bytes
    }
}

/// Togg BLE servislerini keşfeder ve bağlantı durumunu gösterir.
///
/// Bu katman yalnızca keşif/bağlantı yapar. Araç komutu göndermez,
/// karakteristiklere yazmaz ve dijital anahtar üretmez.
@MainActor
@Observable
final class BLEGarageManager: NSObject {
    static let vehicleServiceUUID = CBUUID(string: "F0002412-0451-4000-B000-000000000000")
    static let commandCharacteristicUUID = CBUUID(string: "F0002413-0451-4000-B000-000000000000")
    static let telemetryCharacteristicUUID = CBUUID(string: "F0002415-0451-4000-B000-000000000000")
    static let vehicleTimeCharacteristicUUID = CBUUID(string: "00002A2B-0000-1000-8000-00805F9B34FB")

    enum State: Equatable {
        case unavailable
        case idle
        case scanning
        case connecting
        case connected
        case failed(String)

        var title: String {
            switch self {
            case .unavailable:
                "Bluetooth kullanılamıyor"
            case .idle:
                "Hazır"
            case .scanning:
                "Araç aranıyor"
            case .connecting:
                "Bağlanıyor"
            case .connected:
                "Bağlandı"
            case .failed(let message):
                message
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var discoveredName: String?
    private(set) var discoveredRSSI: Int?
    private(set) var discoveredCharacteristics: [String] = []
    /// Telemetry karakteristiğinden alınan son ham paket.
    /// Protokol şeması doğrulanana kadar byte'lar çözümlenmeden tutulur.
    private(set) var latestTelemetry: Data?
    private(set) var latestTelemetryHex: String?
    /// İmzası araç açık anahtarıyla doğrulanmış son durum. Anahtar yoksa ya da imza hatalıysa nil kalır.
    private(set) var vehicleStatus: ToggBLEProtocol.VehicleStatus?
    private var telemetryVerificationKey: P256.Signing.PublicKey?
    private(set) var lastSignedFrame: SignedBLEFrame?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var vehicleTimeCharacteristic: CBCharacteristic?
    private var pendingChallenge: CheckedContinuation<(Date, Data), Swift.Error>?
    private var pendingAcknowledgement: CheckedContinuation<Data, Swift.Error>?
    private var pendingVehicleDate: Date?
    private var challengeTimeoutTask: Task<Void, Never>?
    private var acknowledgementTimeoutTask: Task<Void, Never>?

    private static let responseTimeout: Duration = .seconds(8)

    private func notifyConnectionChange(title: String, body: String) {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "ble-connection-status",
                content: content,
                trigger: nil
            )

            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.ibrahim.togggaraj.ble.central"
            ]
        )
    }

    func startScan() {
        guard let centralManager, centralManager.state == .poweredOn else {
            state = .unavailable
            return
        }

        discoveredName = nil
        discoveredRSSI = nil
        discoveredCharacteristics = []
        latestTelemetry = nil
        latestTelemetryHex = nil
        vehicleStatus = nil
        peripheral = nil
        state = .scanning
        centralManager.scanForPeripherals(
            withServices: [Self.vehicleServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        AppLog.info(.app, "BLE: araç servisi için tarama başladı")
    }

    /// Telemetri paketlerini doğrulamak için aracın açık anahtarını ayarlar. Anahtar yoksa durum çözülmez.
    func setVehiclePublicKey(_ text: String?) {
        guard let text, let key = try? ToggBLEProtocol.parseVehiclePublicKey(text) else {
            telemetryVerificationKey = nil
            vehicleStatus = nil
            return
        }
        telemetryVerificationKey = key
        if let latestTelemetry {
            applyTelemetryStatus(latestTelemetry)
        }
    }

    private func applyTelemetryStatus(_ packet: Data) {
        guard let key = telemetryVerificationKey else { return }
        do {
            let status = try ToggBLEProtocol.decodeTelemetry(packet, vehicleKey: key)
            // Eski ya da tekrar oynatılan paketi yok sayar.
            guard status.isNewer(than: vehicleStatus) else { return }
            vehicleStatus = status
        } catch {
            AppLog.warning(.app, "BLE: telemetry paketi doğrulanamadı: \(error)")
        }
    }

    func stopScan() {
        centralManager?.stopScan()
        if case .scanning = state {
            state = .idle
        }
    }

    func connectToDiscoveredVehicle() {
        guard let peripheral, let centralManager else { return }
        centralManager.stopScan()
        state = .connecting
        centralManager.connect(peripheral, options: nil)
        AppLog.info(.app, "BLE: keşfedilen cihaza bağlantı başlatıldı")
    }

    func disconnect() {
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        state = .idle
        discoveredCharacteristics = []
        latestTelemetry = nil
        latestTelemetryHex = nil
        vehicleStatus = nil
        commandCharacteristic = nil
        vehicleTimeCharacteristic = nil
        pendingChallenge?.resume(throwing: BLEGarageError.notConnected)
        pendingChallenge = nil
        challengeTimeoutTask?.cancel()
        challengeTimeoutTask = nil
        pendingAcknowledgement?.resume(throwing: BLEGarageError.notConnected)
        pendingAcknowledgement = nil
        acknowledgementTimeoutTask?.cancel()
        acknowledgementTimeoutTask = nil
    }

    /// Şema doğrulanana kadar telemetry paketini yalnızca ham veri olarak okur.
    func readTelemetry() {
        guard let telemetry = peripheral?.services?
            .flatMap({ $0.characteristics ?? [] })
            .first(where: { $0.uuid == Self.telemetryCharacteristicUUID }) else {
            AppLog.warning(.app, "BLE: telemetry karakteristiği hazır değil")
            return
        }

        peripheral?.readValue(for: telemetry)
        peripheral?.setNotifyValue(true, for: telemetry)
        AppLog.info(.app, "BLE: telemetry okunuyor ve bildirimler etkin")
    }

    /// Nonce, zaman damgası ve komut payload'ını Secure Enclave ile imzalar.
    /// Togg wire formatı doğrulanana kadar BLE'ye yazma yapmaz.
    func prepareSignedFrame(
        commandPayload: Data,
        using keyStore: DigitalKeyStore
    ) throws -> SignedBLEFrame {
        let nonce = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000)
        var bytes = Data()
        var bigEndianTimestamp = timestamp.bigEndian
        withUnsafeBytes(of: &bigEndianTimestamp) { bytes.append(contentsOf: $0) }
        bytes.append(nonce)
        bytes.append(commandPayload)

        let frame = SignedBLEFrame(
            timestampMilliseconds: timestamp,
            nonce: nonce,
            commandPayload: commandPayload,
            signature: try keyStore.sign(payload: bytes)
        )
        lastSignedFrame = frame
        AppLog.info(.app, "BLE: imzalı çerçeve hazırlandı; araca gönderilmedi")
        return frame
    }

    /// Bağlı araçtan saati ve tek kullanımlık challenge'ı alır.
    private func readVehicleClockAndChallenge() async throws -> (Date, Data) {
        guard let peripheral,
              let commandCharacteristic,
              let vehicleTimeCharacteristic,
              case .connected = state else {
            throw BLEGarageError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingChallenge = continuation
            pendingVehicleDate = nil
            challengeTimeoutTask?.cancel()
            challengeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.responseTimeout)
                guard !Task.isCancelled else { return }
                self?.timeoutChallenge()
            }

            peripheral.setNotifyValue(true, for: commandCharacteristic)
            peripheral.readValue(for: vehicleTimeCharacteristic)
        }
    }

    /// APK'deki gerçek komut paketini üretir ve bağlı araca yazar.
    /// Challenge/saat alınamaz veya ACK gelmezse yerel araç durumu değiştirilmez.
    func sendToggCommand(
        _ command: ToggBLEProtocol.Command,
        using keyStore: DigitalKeyStore
    ) async throws -> Data {
        guard let peripheral, let commandCharacteristic, case .connected = state else {
            throw BLEGarageError.notConnected
        }
        guard keyStore.certificateBase64 != nil,
              keyStore.vehiclePublicKey != nil else {
            throw BLEGarageError.certificateRequired
        }

        let (vehicleDate, challenge) = try await readVehicleClockAndChallenge()
        let payload = try ToggBLEProtocol.commandPayload(
            command,
            vehicleDate: vehicleDate,
            challenge: challenge
        )
        let signature = try keyStore.signRaw(payload: payload)
        let frame = try ToggBLEProtocol.frame(
            commandPayload: payload,
            rawSignature: signature
        )

        let acknowledgement = try await withCheckedThrowingContinuation { continuation in
            pendingAcknowledgement = continuation
            acknowledgementTimeoutTask?.cancel()
            acknowledgementTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.responseTimeout)
                guard !Task.isCancelled else { return }
                self?.timeoutAcknowledgement()
            }
            peripheral.writeValue(frame, for: commandCharacteristic, type: .withResponse)
        }

        guard acknowledgement == Data([0x12, 0x02, 0x52, 0x00, 0x01, 0x00, 0x00, 0x00]) else {
            throw BLEGarageError.invalidAcknowledgement
        }

        AppLog.info(.app, "BLE: \(command.rawValue) komutu araç ACK ile kabul edildi")
        return acknowledgement
    }

    private func timeoutChallenge() {
        guard let pendingChallenge else { return }
        self.pendingChallenge = nil
        self.pendingVehicleDate = nil
        challengeTimeoutTask = nil
        pendingChallenge.resume(throwing: BLEGarageError.timeout)
    }

    private func timeoutAcknowledgement() {
        guard let pendingAcknowledgement else { return }
        self.pendingAcknowledgement = nil
        acknowledgementTimeoutTask = nil
        pendingAcknowledgement.resume(throwing: BLEGarageError.timeout)
    }

    /// APK'deki gerçek komut paketini üretir. Araç sertifikası doğrulaması ve
    /// challenge okuması tamamlanmadan bu metod çağrılmamalıdır.
    func prepareToggCommandFrame(
        _ command: ToggBLEProtocol.Command,
        vehicleDate: Date,
        challenge: Data,
        using keyStore: DigitalKeyStore
    ) throws -> Data {
        guard case .connected = state else {
            throw BLEGarageError.notConnected
        }
        let payload = try ToggBLEProtocol.commandPayload(
            command,
            vehicleDate: vehicleDate,
            challenge: challenge
        )
        let signature = try keyStore.signRaw(payload: payload)
        let frame = try ToggBLEProtocol.frame(
            commandPayload: payload,
            rawSignature: signature
        )
        AppLog.info(.app, "BLE: APK uyumlu \(command.rawValue) çerçevesi hazırlandı; araca gönderilmedi")
        return frame
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            if let error {
                if characteristic.uuid == Self.vehicleTimeCharacteristicUUID {
                    self.challengeTimeoutTask?.cancel()
                    self.challengeTimeoutTask = nil
                    self.pendingChallenge?.resume(throwing: error)
                    self.pendingChallenge = nil
                } else if characteristic.uuid == Self.commandCharacteristicUUID {
                    self.acknowledgementTimeoutTask?.cancel()
                    self.acknowledgementTimeoutTask = nil
                    self.pendingAcknowledgement?.resume(throwing: error)
                    self.pendingAcknowledgement = nil
                } else {
                    AppLog.error(.app, "BLE: değer okunamadı: \(AppLog.describe(error))")
                }
                return
            }

            guard let value = characteristic.value, !value.isEmpty else {
                return
            }

            if characteristic.uuid == Self.telemetryCharacteristicUUID {
                self.latestTelemetry = value
                self.latestTelemetryHex = value.map { String(format: "%02X", $0) }.joined(separator: " ")
                AppLog.debug(.app, "BLE: telemetry paketi alındı (\(value.count) bayt)")
                self.applyTelemetryStatus(value)
                return
            }

            if characteristic.uuid == Self.vehicleTimeCharacteristicUUID {
                self.challengeTimeoutTask?.cancel()
                self.challengeTimeoutTask = nil
                guard let date = Self.parseVehicleDate(value) else {
                    self.pendingChallenge?.resume(throwing: BLEGarageError.invalidVehicleClock)
                    self.pendingChallenge = nil
                    return
                }
                self.pendingVehicleDate = date
                let challengeRequest = Data([0x13, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
                guard let commandCharacteristic = self.commandCharacteristic else {
                    self.pendingChallenge?.resume(throwing: BLEGarageError.notConnected)
                    self.pendingChallenge = nil
                    return
                }
                peripheral.writeValue(challengeRequest, for: commandCharacteristic, type: .withResponse)
                return
            }

            guard characteristic.uuid == Self.commandCharacteristicUUID else { return }

            if value == Data([0x12, 0x02, 0x52, 0x00, 0x01, 0x00, 0x00, 0x00]) {
                self.acknowledgementTimeoutTask?.cancel()
                self.acknowledgementTimeoutTask = nil
                self.pendingAcknowledgement?.resume(returning: value)
                self.pendingAcknowledgement = nil
                return
            }

            let challengePrefix = Data([0x27, 0x01, 0x0A, 0x00, 0x0A, 0x00, 0x01, 0x00])
            if value.count == 18, value.prefix(8) == challengePrefix {
                let challenge = Data(value.dropFirst(8))
                if let date = self.pendingVehicleDate {
                    self.pendingChallenge?.resume(returning: (date, challenge))
                    self.pendingChallenge = nil
                    self.pendingVehicleDate = nil
                }
            }
        }
    }

    private static func parseVehicleDate(_ value: Data) -> Date? {
        let bytes = [UInt8](value)
        guard bytes.count >= 7 else { return nil }
        let year = Int(bytes[0]) | (Int(bytes[1]) << 8)
        guard (1583...9999).contains(year) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = Int(bytes[2])
        components.day = Int(bytes[3])
        components.hour = Int(bytes[4])
        components.minute = Int(bytes[5])
        components.second = Int(bytes[6])
        return components.date
    }
}

extension BLEGarageManager: CBCentralManagerDelegate {
    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
                  let restoredPeripheral = restoredPeripherals.first else {
                return
            }

            self.peripheral = restoredPeripheral
            self.discoveredName = restoredPeripheral.name ?? "Togg aracı"
            restoredPeripheral.delegate = self

            if UserDefaults.standard.bool(forKey: "proximityUnlockEnabled") {
                self.state = .connecting
                central.connect(restoredPeripheral, options: nil)
                AppLog.info(.app, "BLE: arka plan durumundan araç bağlantısı geri yükleniyor")
            } else {
                self.state = .idle
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                if case .unavailable = state {
                    state = .idle
                }
            case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
                state = .unavailable
            @unknown default:
                state = .unavailable
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.peripheral = peripheral
            self.discoveredName = peripheral.name ?? "Togg aracı"
            self.discoveredRSSI = RSSI.intValue
            self.state = .idle
            self.centralManager?.stopScan()
            AppLog.info(.app, "BLE: araç bulundu (RSSI=\(RSSI.intValue))")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .connected
            peripheral.delegate = self
            peripheral.discoverServices([Self.vehicleServiceUUID])
            self.notifyConnectionChange(
                title: "BLE bağlantısı kuruldu",
                body: "Araç ile Bluetooth bağlantısı hazır."
            )
            AppLog.info(.app, "BLE: araç bağlandı; servis keşfi başladı")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .failed("Bağlantı kurulamadı")
            AppLog.error(.app, "BLE: bağlantı başarısız: \(error.map(AppLog.describe) ?? "bilinmeyen hata")")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .idle
            self.discoveredCharacteristics = []
            self.notifyConnectionChange(
                title: "BLE bağlantısı kesildi",
                body: "Araç Bluetooth bağlantısı kapandı."
            )
            AppLog.info(.app, "BLE: bağlantı kesildi")
        }
    }
}

extension BLEGarageManager: CBPeripheralDelegate {
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.state = .failed("Servisler okunamadı")
                AppLog.error(.app, "BLE: servis keşfi başarısız: \(AppLog.describe(error))")
                return
            }

            let services = peripheral.services ?? []
            for service in services where service.uuid == Self.vehicleServiceUUID {
                peripheral.discoverCharacteristics(
                    [
                        Self.commandCharacteristicUUID,
                        Self.telemetryCharacteristicUUID,
                        Self.vehicleTimeCharacteristicUUID
                    ],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.state = .failed("Karakteristikler okunamadı")
                AppLog.error(.app, "BLE: karakteristik keşfi başarısız: \(AppLog.describe(error))")
                return
            }

            let characteristics = service.characteristics ?? []
            self.commandCharacteristic = characteristics.first {
                $0.uuid == Self.commandCharacteristicUUID
            }
            self.vehicleTimeCharacteristic = characteristics.first {
                $0.uuid == Self.vehicleTimeCharacteristicUUID
            }
            self.discoveredCharacteristics = characteristics
                .map(\.uuid.uuidString)
                .sorted()
            AppLog.info(.app, "BLE: \(self.discoveredCharacteristics.count) karakteristik keşfedildi")
            self.readTelemetry()
        }
    }
}
