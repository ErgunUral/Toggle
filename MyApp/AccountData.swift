import Foundation

nonisolated struct LiveNotification: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
    let date: Date?
    let symbol: String
}

nonisolated struct LiveServiceRecord: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let place: String
    let date: Date?
    let status: String?
}

nonisolated struct LiveSubscription: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
    let isActive: Bool
}

nonisolated struct ClimateState: Sendable, Equatable {
    let active: Bool
    let temperature: Double?
}

nonisolated struct DigitalCertificateResponse: Sendable, Equatable {
    let certificateBase64: String
    let vehiclePublicKey: String?
}

nonisolated struct ClimateCommandResult: Sendable, Equatable {
    let requestID: String?
    let status: String
    let code: String?
}

/// Klima komutunun araçtan dönen son durumu. APK ile aynı sonlanma durumları kullanılır
/// (COMPLETED, FAILED, REJECTED, ERROR, CANCELLED); bunların dışındaki durum araç sonucunun
/// henüz bilinmediği anlamına gelir.
nonisolated enum ClimateCommandError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case failed
    case rejected
    case cancelled
    /// Komut kabul edildi ama akış sonlanma durumu olmadan bitti.
    case unconfirmed

    static func check(_ result: ClimateCommandResult) throws {
        switch result.status.uppercased() {
        case "COMPLETED": return
        case "FAILED", "ERROR": throw ClimateCommandError.failed
        case "REJECTED": throw ClimateCommandError.rejected
        case "CANCELLED": throw ClimateCommandError.cancelled
        default: throw ClimateCommandError.unconfirmed
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .failed: "Araç klima komutunu uygulayamadı."
        case .rejected: "Araç klima komutunu reddetti."
        case .cancelled: "Klima komutu iptal edildi."
        case .unconfirmed: "Komut gönderildi ama aracın uyguladığı doğrulanamadı. Klima durumunu kontrol et."
        }
    }
}

extension ClimateCommandError: LocalizedError {
    var errorDescription: String? { String(localized: localizedStringResource) }
}

nonisolated enum AccountPayload {
    static func items(_ json: [String: Any], preferredKeys: [String]) -> [[String: Any]] {
        for key in preferredKeys {
            if let rows = json[key] as? [[String: Any]] {
                return rows
            }
        }

        if let rows = json["data"] as? [[String: Any]] {
            return rows
        }

        if let data = json["data"] as? [String: Any] {
            return items(data, preferredKeys: preferredKeys)
        }

        if let rows = json["items"] as? [[String: Any]] {
            return rows
        }

        if let rows = json["results"] as? [[String: Any]] {
            return rows
        }

        return []
    }

    static func text(_ dict: [String: Any], _ keys: String...) -> String? {
        text(dict, keys: keys)
    }

    private static func text(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            switch dict[key] {
            case let value as String where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            case let value as NSNumber:
                return value.stringValue
            default:
                continue
            }
        }
        return nil
    }

    static func date(_ dict: [String: Any], _ keys: String...) -> Date? {
        guard let raw = text(dict, keys: keys) else { return nil }
        return ServerAnalytics.parseDate(raw)
    }

    static func bool(_ dict: [String: Any], _ keys: String...) -> Bool? {
        for key in keys {
            switch dict[key] {
            case let value as Bool:
                return value
            case let value as NSNumber:
                return value.boolValue
            case let value as String:
                switch value.lowercased() {
                case "true", "1", "active", "aktif": return true
                case "false", "0", "inactive", "pasif": return false
                default: continue
                }
            default:
                continue
            }
        }
        return nil
    }
}
