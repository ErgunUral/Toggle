import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - Tema

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, ocean, sunset

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        case .ocean: "Okyanus"
        case .sunset: "Günbatımı"
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .system: "Cihaz görünümünü kullan"
        case .light: "Aydınlık ve sade"
        case .dark: "Koyu ve sakin"
        case .ocean: "Derin mavi ve serin"
        case .sunset: "Sıcak turuncu tonlar"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .sunset: .light
        case .dark, .ocean: .dark
        }
    }
}

enum Theme {
    /// Seçili temaya göre markanın turkuaz ve elektrik mavisi tonlarını korur.
    static func accent(for scheme: ColorScheme, theme: AppTheme = .system) -> Color {
        switch theme {
        case .ocean:
            return ToggGarageBrand.electric
        case .sunset:
            return ToggGarageBrand.signal
        case .dark:
            return ToggGarageBrand.turquoiseLight
        case .light:
            return ToggGarageBrand.turquoise
        case .system:
            return scheme == .dark
                ? ToggGarageBrand.turquoiseLight
                : ToggGarageBrand.turquoise
        }
    }

    static func background(for scheme: ColorScheme, theme: AppTheme) -> Color {
        switch theme {
        case .ocean, .dark:
            return ToggGarageBrand.midnight
        case .sunset:
            return Color(red: 0.98, green: 0.94, blue: 0.89)
        case .light:
            return ToggGarageBrand.cloud
        case .system:
            return scheme == .dark
                ? ToggGarageBrand.midnight
                : ToggGarageBrand.cloud
        }
    }
}

/// Ekranın arkasındaki, üstten turkuaz ışık süzülen zemin.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [ToggGarageBrand.midnight, ToggGarageBrand.graphite]
                    : [ToggGarageBrand.cloud, Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Theme.accent(for: scheme, theme: theme).opacity(scheme == .dark ? 0.26 : 0.18),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Bileşenler

extension View {
    /// Liquid Glass yüzeyli kart.
    func glassCard(cornerRadius: CGFloat = 26) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(ToggGarageBrand.turquoise.opacity(0.07)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        ToggGarageBrand.turquoise.opacity(0.10),
                        lineWidth: 1
                    )
            }
    }
}

extension Double {
    func decimal(_ digits: Int = 0) -> String {
        formatted(.number.precision(.fractionLength(digits)))
    }
}

extension Date {
    private static let turkish = Locale(identifier: "tr_TR")

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = turkish
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private static func dateFormatter(date: DateFormatter.Style, time: DateFormatter.Style) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = turkish
        formatter.dateStyle = date
        formatter.timeStyle = time
        return formatter
    }

    private static let shortDateTimeFormatter = dateFormatter(date: .medium, time: .short)
    private static let longDateFormatter = dateFormatter(date: .long, time: .none)

    // Ortam yereli cihaz diline bağlı kalabildiğinden, bu biçimler yereli açıkça Türkçe verir.

    /// "6 dakika önce"
    var relativeText: String { Self.relativeFormatter.localizedString(for: self, relativeTo: .now) }

    /// "16 Eki 2026 12:49"
    var shortDateTimeText: String { Self.shortDateTimeFormatter.string(from: self) }

    /// "16 Ekim 2026"
    var longDateText: String { Self.longDateFormatter.string(from: self) }
}

extension Optional where Wrapped == Double {
    /// Değer yoksa "—" döner.
    func decimal(_ digits: Int = 0) -> String {
        map { $0.decimal(digits) } ?? "—"
    }
}

struct SectionTitle: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// 0...1 arası değeri halka olarak gösterir.
struct RingGauge: View {
    let value: Double
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: value)
    }
}

struct MeterBar: View {
    let value: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 7)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
            }
            .animation(.smooth, value: value)
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Araç görselleri

/// Araç PNG'lerini asset kataloğundan ya da uygulama paketinden yükler ve önbelleğe alır.
enum VehicleImageLoader {
    private static let cache = NSCache<NSString, PlatformImage>()

    static func image(named name: String) -> PlatformImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let path = Bundle.main.path(forResource: name, ofType: "png")
            ?? Bundle.main.path(forResource: name, ofType: "png", inDirectory: "VehicleImages")
        guard let image = PlatformImage(named: name) ?? path.flatMap({ PlatformImage(contentsOfFile: $0) }) else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

struct VehicleImageView: View {
    let name: String

    var body: some View {
        if let image = VehicleImageLoader.image(named: name) {
            Group {
                #if canImport(UIKit)
                Image(uiImage: image).resizable()
                #else
                Image(nsImage: image).resizable()
                #endif
            }
            .scaledToFit()
        } else {
            Image(systemName: "car.side")
                .resizable()
                .scaledToFit()
                .padding(40)
                .foregroundStyle(.tertiary)
        }
    }
}
