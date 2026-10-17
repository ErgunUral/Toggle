import SwiftUI

struct ThemeView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Uygulamanın görünümünü seç")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                LazyVStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            themeRaw = theme.rawValue
                        } label: {
                            ThemeOptionCard(
                                theme: theme,
                                isSelected: selectedTheme == theme,
                                previewScheme: previewScheme(for: theme)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .background { AppBackground() }
        .navigationTitle("Tema")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func previewScheme(for theme: AppTheme) -> ColorScheme {
        theme.colorScheme ?? scheme
    }
}

private struct ThemeOptionCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let previewScheme: ColorScheme

    var body: some View {
        let accent = Theme.accent(for: previewScheme, theme: theme)
        let background = Theme.background(for: previewScheme, theme: theme)

        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(background)
                Circle()
                    .fill(accent)
                    .frame(width: 28, height: 28)
                Image(systemName: theme == .sunset ? "sun.horizon.fill" : "car.side.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(background)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(theme.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(isSelected ? accent : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(theme.title)
        .accessibilityValue(isSelected ? "Seçili" : theme.description)
    }
}

#Preview {
    NavigationStack {
        ThemeView()
    }
}
