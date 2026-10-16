import CryptoKit
import Foundation
import Observation
import Security

enum DigitalKeyStoreError: LocalizedError {
    case secureEnclaveUnavailable
    case keyGenerationFailed
    case keyReadFailed
    case keyDeleteFailed

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

    private(set) var hasLocalKey = false
    private(set) var publicKeyBase64: String?
    private(set) var errorMessage: String?

    init() {
        loadExistingKey()
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
        errorMessage = nil
        AppLog.info(.app, "Dijital anahtar: yerel anahtar silindi")
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
}
