import SwiftUI

/// Togg Garajım uygulamasının ortak marka dili.
enum ToggGarageBrand {
    static let midnight = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let graphite = Color(red: 0.11, green: 0.14, blue: 0.17)
    static let cloud = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let turquoise = Color(red: 0.04, green: 0.61, blue: 0.64)
    static let turquoiseLight = Color(red: 0.35, green: 0.82, blue: 0.80)
    static let electric = Color(red: 0.42, green: 0.72, blue: 0.98)
    static let signal = Color(red: 0.98, green: 0.68, blue: 0.22)

    static let primaryGradient = LinearGradient(
        colors: [turquoise, electric],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let darkGradient = LinearGradient(
        colors: [midnight, graphite],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tagline = "Bağlı yaşamın akıllı garajı"
}

struct BrandLockup: View {
    var showsTagline = true
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            BrandMark(size: compact ? 34 : 44)

            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text("Togg")
                    .font(.system(size: compact ? 17 : 21, weight: .bold, design: .rounded))
                    .tracking(-0.4)

                Text("Garajım")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if showsTagline && !compact {
                    Text(ToggGarageBrand.tagline)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Togg Garajım, \(ToggGarageBrand.tagline)")
    }
}

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(ToggGarageBrand.primaryGradient)

            Image(systemName: "car.side.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: ToggGarageBrand.turquoise.opacity(0.28), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

struct BrandSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrandPageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(ToggGarageBrand.primaryGradient, in: .rect(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}
