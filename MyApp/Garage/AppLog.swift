import Foundation
import OSLog
import Observation

// MARK: - Modeller

nonisolated enum LogCategory: String, CaseIterable, Identifiable, Sendable {
    case app = "Uygulama"
    case auth = "Giriş"
    case network = "Ağ"
    case parse = "Ayrıştırma"
    case refresh = "Yenileme"

    var id: String { rawValue }
}

nonisolated enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

nonisolated struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let category: LogCategory
    let message: String

    /// Paylaşılan metindeki tek satır.
    var line: String {
        let time = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return "\(time) [\(level.rawValue)] [\(category.rawValue)] \(message)"
    }
}

// MARK: - Uygulama içi tampon

/// Son kayıtları ekranda göstermek için tutar. Sistem günlüğüne ayrıca yazılır.
@MainActor @Observable
final class LogStore {
    static let shared = LogStore()

    private(set) var entries: [LogEntry] = []
    private let limit = 500

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    func clear() { entries.removeAll() }

    var exportText: String {
        entries.map(\.line).joined(separator: "\n")
    }
}

// MARK: - Günlük yazıcı

/// Her iş parçacığından/actor'dan çağrılabilir.
///
/// Günlüğe belirteç, parola, `code`/`state`/`verifier`, konum koordinatı, tam VIN ve
/// ham yanıt değerleri yazılmaz. Yanıtlarda yalnızca anahtar adları kaydedilir.
nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TogGarajim"

    static func debug(_ category: LogCategory, _ message: String) { write(.debug, category, message) }
    static func info(_ category: LogCategory, _ message: String) { write(.info, category, message) }
    static func warning(_ category: LogCategory, _ message: String) { write(.warning, category, message) }
    static func error(_ category: LogCategory, _ message: String) { write(.error, category, message) }

    /// Kategori başına bir kez oluşturulur.
    private static let loggers = Dictionary(uniqueKeysWithValues: LogCategory.allCases.map {
        ($0, Logger(subsystem: subsystem, category: $0.rawValue))
    })

    private static func write(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        guard let logger = loggers[category] else { return }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        let entry = LogEntry(date: .now, level: level, category: category, message: message)
        Task { @MainActor in LogStore.shared.append(entry) }
    }

    // MARK: Yardımcılar

    /// TRZ••••••••••1234 biçimine çevirir.
    static func maskVIN(_ vin: String) -> String {
        guard vin.count > 7 else { return String(repeating: "•", count: vin.count) }
        return vin.prefix(3) + String(repeating: "•", count: vin.count - 7) + vin.suffix(4)
    }

    /// Geçen süreyi "123 ms" olarak yazar.
    static func ms(since start: ContinuousClock.Instant) -> String {
        let parts = (ContinuousClock.now - start).components
        let value = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        return "\(Int(value.rounded())) ms"
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "URLError(\(urlError.code.rawValue)) \(urlError.localizedDescription)"
        }
        return "\(type(of: error)): \(error.localizedDescription)"
    }

    /// JSON'un yalnızca anahtar yapısını döner; değerleri içermez.
    static func shape(_ value: Any?, depth: Int = 6) -> String {
        String(describeShape(value, depth: depth).prefix(2500))
    }

    private static func describeShape(_ value: Any?, depth: Int) -> String {
        switch value {
        case let dict as [String: Any]:
            guard depth > 0 else { return "{…}" }
            let parts = dict.keys.sorted().map { key -> String in
                let child = dict[key]
                let isContainer = child is [String: Any] || child is [Any]
                return isContainer ? "\(key):\(describeShape(child, depth: depth - 1))" : key
            }
            return "{" + parts.joined(separator: ",") + "}"
        case let array as [Any]:
            let first = array.first.map { "×" + describeShape($0, depth: depth - 1) } ?? ""
            return "[\(array.count)\(first)]"
        default:
            return ""
        }
    }
}
