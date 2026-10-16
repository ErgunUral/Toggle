import SwiftUI

struct RootView: View {
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = GarageStore()

    var body: some View {
        ThemedTabs()
            .environment(store)
            // Metinler Türkçe olduğundan tarih ve sayı biçimleri de Türkçe olur.
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .preferredColorScheme(AppTheme(rawValue: themeRaw)?.colorScheme)
            // Uygulama öne gelince oturumu okur; açıkken canlı veriyi 2 dakikada bir yeniler.
            .task(id: scenePhase) {
                AppLog.debug(.app, "scenePhase=\(String(describing: scenePhase))")
                guard scenePhase == .active else { return }
                AppLog.info(.app, "Uygulama aktif · iOS \(ProcessInfo.processInfo.operatingSystemVersionString) · yerel=\(Locale.current.identifier)")
                let probe = Date.now.addingTimeInterval(-120)
                AppLog.debug(.app, "Tarih biçimi denemesi: göreli=\(probe.relativeText) · kısa=\(probe.shortDateTimeText) · uzun=\(probe.longDateText)")
                await store.syncSignInState()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled else { break }
                    if store.isSignedIn {
                        AppLog.debug(.refresh, "Otomatik yenileme zamanı (120 sn)")
                        await store.refresh()
                    }
                }
            }
    }
}

/// preferredColorScheme çözüldükten sonraki ortamı okuyup vurgu rengini ayarlar.
private struct ThemedTabs: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(GarageStore.self) private var store

    var body: some View {
        TabView {
            Tab("Araç", systemImage: "car.side.fill") { HomeView() }
            // Klima ekranı örnek ve canlı modda aynı sekmeden açılır.
            Tab("Klima", systemImage: "fan.fill") { ClimateView() }
            Tab("Şarj", systemImage: "bolt.fill") { ChargeView() }
            Tab("Konum", systemImage: "location.fill") { LocationView() }
            Tab("Daha fazla", systemImage: "ellipsis") { MoreView() }
        }
        .tint(Theme.accent(for: scheme))
    }
}

#Preview {
    RootView()
}
