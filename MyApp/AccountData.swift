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

nonisolated struct ClimateCommandResult: Sendable, Equatable {
    let requestID: String?
    let status: String
    let code: String?
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
