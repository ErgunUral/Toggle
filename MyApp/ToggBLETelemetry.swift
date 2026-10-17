import CryptoKit
import Foundation

/// APK'deki `BleProtocol.telemetry` ile aynı 93 baytlık imzalı araç durum paketi.
/// Paket, araç açık anahtarıyla doğrulanmadan çözümlenmez; APK de imzasız veriyi kabul etmez.
extension ToggBLEProtocol {
    struct VehicleStatus: Equatable, Sendable {
        /// Bayt 10. APK'deki hızlı işlemde 1 = kilitli, 2 = açık olarak kullanılır.
        let lockRaw: UInt8
        /// Bayt 11–14. APK bu değerleri yorumlamadan iletir; anlamları doğrulanmadı.
        let doorsRaw: [UInt8]
        /// Bayt 15. APK'ye göre 0 = bagaj kapalı, 1 = aralık.
        let trunkRaw: UInt8
        /// Bayt 22. 2 = bekleme, 3 = aksesuar, 4 = hazır.
        let powerRaw: UInt8
        /// Bayt 23. Eski paketin tekrar oynatılmasını ayırt etmek için artan sayaç.
        let counter: UInt8

        enum Lock { case locked, unlocked, unknown }
        enum Trunk { case closed, ajar, unknown }
        enum Power { case standby, accessory, ready, unknown }

        var lock: Lock {
            switch lockRaw {
            case 1: .locked
            case 2: .unlocked
            default: .unknown
            }
        }

        var trunk: Trunk {
            switch trunkRaw {
            case 0: .closed
            case 1: .ajar
            default: .unknown
            }
        }

        var power: Power {
            switch powerRaw {
            case 2: .standby
            case 3: .accessory
            case 4: .ready
            default: .unknown
            }
        }

        /// APK'deki sayaç kuralı: ilerleme 1...127 (mod 256) ise paket yenidir, aksi halde eski/tekrardır.
        func isNewer(than previous: VehicleStatus?) -> Bool {
            guard let previous else { return true }
            let step = (Int(counter) - Int(previous.counter) + 256) % 256
            return step != 0 && step <= 127
        }
    }

    enum TelemetryError: Swift.Error, Equatable {
        case invalidPacket
        case invalidKey
        case invalidSignature
    }

    /// Paketi doğrular ve çözer. Geçersiz biçimde ya da imza hatalıysa hata fırlatır.
    static func decodeTelemetry(_ packet: Data, vehicleKey: P256.Signing.PublicKey) throws -> VehicleStatus {
        let bytes = [UInt8](packet)
        guard bytes.count == 93,
              bytes[0] == 38, bytes[2] == 85, bytes[3] == 0, bytes[4] == 85, bytes[5] == 0 else {
            throw TelemetryError.invalidPacket
        }

        let signedPart = Data(bytes[8..<29])
        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: Data(bytes[29..<93])),
              vehicleKey.isValidSignature(signature, for: signedPart) else {
            throw TelemetryError.invalidSignature
        }

        return VehicleStatus(
            lockRaw: bytes[10],
            doorsRaw: Array(bytes[11...14]),
            trunkRaw: bytes[15],
            powerRaw: bytes[22],
            counter: bytes[23]
        )
    }

    /// APK'deki `carKey` ile aynı biçimler: 128 ya da `04` + 128 onaltılık, ya da Base64
    /// (ham 64 bayt, 65 baytlık x9.63 ya da X.509 SPKI).
    static func parseVehiclePublicKey(_ text: String) throws -> P256.Signing.PublicKey {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            trimmed.removeFirst(2)
        }

        let data: Data
        if trimmed.range(of: "^(04)?[0-9a-fA-F]{128}$", options: .regularExpression) != nil {
            data = Data(hexString: trimmed)
        } else if let decoded = Data(base64Encoded: trimmed) {
            data = decoded
        } else {
            throw TelemetryError.invalidKey
        }

        switch data.count {
        case 64:
            if let key = try? P256.Signing.PublicKey(rawRepresentation: data) { return key }
        case 65:
            if let key = try? P256.Signing.PublicKey(x963Representation: data) { return key }
        default:
            if let key = try? P256.Signing.PublicKey(derRepresentation: data) { return key }
        }
        throw TelemetryError.invalidKey
    }
}

private extension Data {
    /// Yalnızca geçerli onaltılık metinle çağrılır (çağıran regex ile doğrular).
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
