import CryptoKit
import Foundation
import Observation
import Security

enum DigitalKeyStoreError: LocalizedError {
    case secureEnclaveUnavailable
    case keyGenerationFailed
    case keyReadFailed
    case keyDeleteFailed
    case invalidVIN
    case keyRequiredForAssociation
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            "Bu cihaz Secure Enclave desteklemiyor."
        case .keyGenerationFailed:
            "Güvenli anahtar çifti oluşturulamadı."
        case .keyReadFailed:
            "Güvenli anahtar çifti okunamadı."
        case .keyDeleteFailed:
            "Güvenli anahtar çifti silinemedi."
        case .invalidVIN:
            "Geçerli bir VIN girilmedi."
        case .keyRequiredForAssociation:
            "Önce güvenli anahtar çifti oluşturulmalı."
        case .signingFailed:
            "İmzalama anahtarı kullanılamadı."
        }
    }
}

/// Dijital anahtar kaydının güvenli yerel kısmı.
///
/// Bu store yalnızca cihaz içi P-256 imzalama anahtarını Secure Enclave'de
/// oluşturur ve anahtarın sarmalanmış temsilini Keychain'de saklar.
/// Araç sertifikası, VIN eşleştirmesi ve BLE komutu bu aşamada yoktur.
@MainActor
@Observable
final class DigitalKeyStore {
    private static let service = "garajim.digital-key"
    private static let account = "vehicle-signing-key"
    private static let associationService = "garajim.digital-key.association"
    private static let associationAccount = "associated-vin"
    private static let certificateService = "garajim.digital-key.certificate"
    private static let certificateAccount = "vehicle-certificate"

    private struct CertificateRecord: Codable {
        let vin: String
        let certificateBase64: String
        let vehiclePublicKey: String?
    }

    private(set) var hasLocalKey = false
    private(set) var publicKeyBase64: String?
    private(set) var associatedVIN: String?
    private(set) var certificateVIN: String?
    private(set) var certificateBase64: String?
    private(set) var vehiclePublicKey: String?
    private(set) var errorMessage: String?

    init() {
        loadExistingKey()
        loadAssociation()
        loadCertificate()
    }

    func createKeyIfNeeded() {
        guard !hasLocalKey else { return }
        do {
            try createKey()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLog.error(.app, "Dijital anahtar: \(AppLog.describe(error))")
        }
    }

    func deleteLocalKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            errorMessage = DigitalKeyStoreError.keyDeleteFailed.localizedDescription
            AppLog.error(.app, "Dijital anahtar silinemedi, OSStatus=\(status)")
            return
        }

        hasLocalKey = false
        publicKeyBase64 = nil
        removeAssociation()
        clearCertificate()
        errorMessage = nil
        AppLog.info(.app, "Dijital anahtar: yerel anahtar silindi")
    }

    /// Yerel public key'in hangi araç için hazırlandığını Keychain'de saklar.
    /// Sunucu sertifikası alınmadan araç üzerinde yetkilendirme oluşturmaz.
    func associate(with vin: String) {
        guard hasLocalKey else {
            errorMessage = DigitalKeyStoreError.keyRequiredForAssociation.localizedDescription
            return
        }

        let normalizedVIN = vin.uppercased()
        guard normalizedVIN.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            errorMessage = DigitalKeyStoreError.invalidVIN.localizedDescription
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.associationService,
            kSecAttrAccount as String: Self.associationAccount
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = Data(normalizedVIN.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            errorMessage = DigitalKeyStoreError.keyGenerationFailed.localizedDescription
            return
        }

        associatedVIN = normalizedVIN
        errorMessage = nil
        AppLog.info(.app, "Dijital anahtar: yerel public key VIN ile ilişkilendirildi")
    }

    func removeAssociation() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.associationService,
            kSecAttrAccount as String: Self.associationAccount
        ]
        SecItemDelete(query as CFDictionary)
        associatedVIN = nil
        errorMessage = nil
    }

    /// Sunucudan alınan sertifikayı VIN'e bağlayarak Keychain'de saklar.
    /// Araç doğrulama anahtarı yoksa fiziksel BLE komutları etkinleştirilmez.
    func installCertificate(_ response: DigitalCertificateResponse, for vin: String) {
        let normalizedVIN = vin.uppercased()
        guard normalizedVIN.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil,
              !response.certificateBase64.isEmpty else {
            errorMessage = DigitalKeyStoreError.invalidVIN.localizedDescription
            return
        }

        let record = CertificateRecord(
            vin: normalizedVIN,
            certificateBase64: response.certificateBase64,
            vehiclePublicKey: response.vehiclePublicKey
        )
        guard let data = try? JSONEncoder().encode(record) else {
            errorMessage = "Dijital anahtar sertifikası saklanamadı."
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.certificateService,
            kSecAttrAccount as String: Self.certificateAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            errorMessage = "Dijital anahtar sertifikası saklanamadı."
            return
        }

        certificateVIN = record.vin
        certificateBase64 = record.certificateBase64
        vehiclePublicKey = record.vehiclePublicKey
        errorMessage = nil
        AppLog.info(.app, "Dijital anahtar sertifikası Keychain'e kaydedildi")
    }

    func clearCertificate() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.certificateService,
            kSecAttrAccount as String: Self.certificateAccount
        ]
        SecItemDelete(query as CFDictionary)
        certificateVIN = nil
        certificateBase64 = nil
        vehiclePublicKey = nil
    }

    /// Nonce/zaman/payload gibi doğrulanmış bir BLE çerçevesini imzalamak için
    /// Secure Enclave anahtarını kullanır. Bu metod araçla iletişim kurmaz.
    func sign(payload: Data) throws -> Data {
        guard hasLocalKey else {
            throw DigitalKeyStoreError.keyRequiredForAssociation
        }

        do {
            let privateKey = try loadPrivateKey()
            return try privateKey.signature(for: payload).derRepresentation
        } catch {
            errorMessage = DigitalKeyStoreError.signingFailed.localizedDescription
            AppLog.error(.app, "Dijital anahtar: payload imzalanamadı")
            throw DigitalKeyStoreError.signingFailed
        }
    }

    /// APK'nin BLE çerçevesinde kullandığı sabit 64 baytlık r||s imzasını üretir.
    func signRaw(payload: Data) throws -> Data {
        try ToggBLEProtocol.rawSignature(fromDER: sign(payload: payload))
    }

    private func loadPrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            throw DigitalKeyStoreError.keyReadFailed
        }

        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
    }

    private func createKey() throws {
        guard SecureEnclave.isAvailable else {
            throw DigitalKeyStoreError.secureEnclaveUnavailable
        }

        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        )

        guard let access else {
            throw DigitalKeyStoreError.keyGenerationFailed
        }

        let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
            compactRepresentable: true,
            accessControl: access
        )

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: privateKey.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw DigitalKeyStoreError.keyGenerationFailed
        }

        hasLocalKey = true
        publicKeyBase64 = privateKey.publicKey.x963Representation.base64EncodedString()
        AppLog.info(.app, "Dijital anahtar: Secure Enclave P-256 anahtarı hazır")
    }

    private func loadExistingKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let privateKey = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) else {
            return
        }

        hasLocalKey = true
        publicKeyBase64 = privateKey.publicKey.x963Representation.base64EncodedString()
    }

    private func loadAssociation() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.associationService,
            kSecAttrAccount as String: Self.associationAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let vin = String(data: data, encoding: .utf8) else {
            return
        }

        associatedVIN = vin
    }

    private func loadCertificate() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.certificateService,
            kSecAttrAccount as String: Self.certificateAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let record = try? JSONDecoder().decode(CertificateRecord.self, from: data) else {
            return
        }

        certificateVIN = record.vin
        certificateBase64 = record.certificateBase64
        vehiclePublicKey = record.vehiclePublicKey
    }
}
