import CoreBluetooth
import Foundation
import Observation

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

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard let centralManager, centralManager.state == .poweredOn else {
            state = .unavailable
            return
        }

        discoveredName = nil
        discoveredRSSI = nil
        discoveredCharacteristics = []
        peripheral = nil
        state = .scanning
        centralManager.scanForPeripherals(
            withServices: [Self.vehicleServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        AppLog.info(.app, "BLE: araç servisi için tarama başladı")
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
    }
}

extension BLEGarageManager: CBCentralManagerDelegate {
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
                    [Self.commandCharacteristicUUID, Self.telemetryCharacteristicUUID],
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

            self.discoveredCharacteristics = (service.characteristics ?? [])
                .map(\.uuid.uuidString)
                .sorted()
            AppLog.info(.app, "BLE: \(self.discoveredCharacteristics.count) karakteristik keşfedildi")
        }
    }
}
