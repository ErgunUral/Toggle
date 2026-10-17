import CryptoKit
import Foundation

/// Togg Garajım APK'sindeki BLE komut çerçevesinin iOS karşılığı.
/// Araç anahtarı/sertifika doğrulanmadan hiçbir I/O gerçekleştirmez.
enum ToggBLEProtocol {
    enum Command: String, CaseIterable, Sendable {
        case unlock
        case lock
        case trunkOpen
        case trunkClose
        case windowsOpen
        case windowsClose
        case driveAuthorize

        fileprivate var opcode: UInt8 {
            switch self {
            case .unlock: 2
            case .lock: 1
            case .trunkOpen: 4
            case .trunkClose: 5
            case .windowsOpen: 6
            case .windowsClose: 7
            case .driveAuthorize: 14
            }
        }
    }

    enum Error: LocalizedError {
        case invalidChallenge
        case invalidVehicleTime
        case unsupportedSignature
        case invalidSignature

        var errorDescription: String? {
            switch self {
            case .invalidChallenge:
                "Araçtan geçerli bir Bluetooth komut sorusu alınamadı."
            case .invalidVehicleTime:
                "Araç saati geçersiz."
            case .unsupportedSignature:
                "İmzalama sonucu desteklenmiyor."
            case .invalidSignature:
                "İmza uzunluğu geçersiz."
            }
        }
    }

    /// APK'de araçtan okunan komut sorusu için kullanılan 10 baytlık değeri doğrular.
    static func validateChallenge(_ challenge: Data) throws -> Data {
        guard challenge.count == 10 else {
            throw Error.invalidChallenge
        }
        return challenge
    }

    /// APK'deki B.g(...) ile aynı sıralamada komut gövdesi üretir:
    /// opcode + yıl (big-endian byte order) + ay + gün + saat + dakika + saniye + challenge.
    static func commandPayload(
        _ command: Command,
        vehicleDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian),
        challenge: Data
    ) throws -> Data {
        let challenge = try validateChallenge(challenge)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: vehicleDate
        )

        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second,
              (1583...9999).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second) else {
            throw Error.invalidVehicleTime
        }

        var payload = Data([
            command.opcode,
            UInt8((year >> 8) & 0xff),
            UInt8(year & 0xff),
            UInt8(month),
            UInt8(day),
            UInt8(hour),
            UInt8(minute),
            UInt8(second)
        ])
        payload.append(challenge)
        return payload
    }

    /// BLE'ye yazılan paket: APK'deki komut başlığı + komut gövdesi + 64 baytlık
    /// r||s ECDSA imzası.
    static func frame(commandPayload: Data, rawSignature: Data) throws -> Data {
        guard rawSignature.count == 64 else {
            throw Error.invalidSignature
        }

        var frame = Data([0x23, 0x01, 0x52, 0x00, 0x52, 0x00, 0x01, 0x00])
        frame.append(commandPayload)
        frame.append(rawSignature)
        return frame
    }

    /// CryptoKit'in DER imzasını APK'nin kullandığı sabit 64 baytlık r||s biçimine çevirir.
    static func rawSignature(fromDER der: Data) throws -> Data {
        let bytes = [UInt8](der)
        guard bytes.count >= 8, bytes[0] == 0x30 else {
            throw Error.unsupportedSignature
        }

        var index = 2
        guard index < bytes.count, bytes[index] == 0x02 else {
            throw Error.unsupportedSignature
        }
        let rLength = Int(bytes[index + 1])
        index += 2
        guard index + rLength + 2 <= bytes.count else {
            throw Error.unsupportedSignature
        }
        let r = Array(bytes[index..<(index + rLength)])
        index += rLength
        guard bytes[index] == 0x02 else {
            throw Error.unsupportedSignature
        }
        let sLength = Int(bytes[index + 1])
        index += 2
        guard index + sLength == bytes.count else {
            throw Error.unsupportedSignature
        }
        let s = Array(bytes[index..<(index + sLength)])

        func normalize(_ value: [UInt8]) -> [UInt8]? {
            var value = value
            while value.count > 32, value.first == 0 {
                value.removeFirst()
            }
            guard value.count <= 32 else { return nil }
            return Array(repeating: UInt8(0), count: 32 - value.count) + value
        }

        guard let normalizedR = normalize(r), let normalizedS = normalize(s) else {
            throw Error.unsupportedSignature
        }
        return Data(normalizedR + normalizedS)
    }
}
