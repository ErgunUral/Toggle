import SwiftUI
import Charts
import AuthenticationServices

struct MoreView: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { JourneyView() } label: {
                        row("Seyahatname", "Sürüş geçmişi ve tüketim", "safari")
                    }
                    NavigationLink { DigitalKeyView() } label: {
                        row("Dijital anahtar", "Telefonunu anahtar olarak kullan", "key.horizontal.fill")
                    }
                    NavigationLink { ServiceView() } label: {
                        row("Servis", "Bakım kayıtları", "wrench.and.screwdriver.fill")
                    }
                    NavigationLink { SubscriptionsView() } label: {
                        row("Abonelikler", "Bağlantı ve hizmet paketleri", "bag.fill")
                    }
                }
                Section {
                    NavigationLink { NotificationsView() } label: {
                        row("Bildirimler", "Araçtan gelen uyarılar", "bell.fill")
                    }
                    NavigationLink { SpecsView() } label: {
                        row("Teknik bilgiler", "\(store.snapshot.model) · \(store.snapshot.edition)", "info.circle.fill")
                    }
                    NavigationLink { SettingsView() } label: {
                        row("Ayarlar", "Bağlantı, görünüm ve araç rengi", "gearshape.fill")
                    }
                } footer: {
                    if store.snapshot.isLive {
                        Text("Servis, abonelik, bildirim, dijital anahtar ve teknik bilgiler henüz canlı değil; örnek veri gösterir.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Daha fazla")
        }
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Alt ekranlar

/// Alt ekranlarda ortak liste zemini.
private struct ListScreen<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        List { content }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayModeInline()
    }
}

struct NotificationsView: View {
    var body: some View {
        ListScreen(title: "Bildirimler") {
            ForEach(SampleData.notifications) { item in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        Text(item.date.relativeText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: item.symbol).foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ServiceView: View {
    var body: some View {
        ListScreen(title: "Servis") {
            ForEach(SampleData.serviceRecords) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title).font(.subheadline.weight(.semibold))
                    Text(record.place).font(.caption).foregroundStyle(.secondary)
                    Text(record.date.longDateText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct SubscriptionsView: View {
    var body: some View {
        ListScreen(title: "Abonelikler") {
            ForEach(SampleData.subscriptions) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.isActive ? "Aktif" : "Pasif")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(item.isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15), in: .capsule)
                        .foregroundStyle(item.isActive ? Color.accentColor : .secondary)
                }
                .padding(.vertical, 4)
            }
            Section {} footer: {
                Text("Abonelik satın alma veya değişikliği bu sürümde yapılmaz.")
            }
        }
    }
}

private struct DigitalKeyView: View {
    var body: some View {
        ListScreen(title: "Dijital anahtar") {
            ForEach(SampleData.digitalKeys) { key in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name).font(.subheadline.weight(.semibold))
                        Text(key.detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: key.symbol).foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            }
            Section {} footer: {
                Text("Örnek veri. Bluetooth eşleştirme ve araç sahipliği doğrulaması henüz uygulanmadı.")
            }
        }
    }
}

private struct SpecsView: View {
    var body: some View {
        ListScreen(title: "Teknik bilgiler") {
            ForEach(SampleData.specs, id: \.0) { spec in
                LabeledContent(spec.0, value: spec.1)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(GarageStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webSession
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue

    var body: some View {
        ListScreen(title: "Ayarlar") {
            Section("Görünüm") {
                Picker("Tema", selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                LabeledContent("Veri kaynağı", value: store.snapshot.isLive ? "Canlı · Togg" : "Örnek veri")
                if store.isSignedIn {
                    Button("Bilgileri yenile", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                    .disabled(store.isRefreshing)
                    if store.vehicles.count > 1 {
                        Picker("Araç", selection: Binding(
                            get: { store.selectedVIN ?? "" },
                            set: { vin in Task { await store.selectVehicle(vin) } }
                        )) {
                            ForEach(store.vehicles) { vehicle in
                                Text(vehicle.name.isEmpty ? vehicle.vin : vehicle.name).tag(vehicle.vin)
                            }
                        }
                    }
                    Button("Oturumu kapat", role: .destructive) {
                        Task { await store.signOut() }
                    }
                } else {
                    Button("Togg ID ile giriş yap", systemImage: "person.badge.key") {
                        Task { await store.signIn(using: webSession) }
                    }
                    .disabled(store.isRefreshing)
                }
                if let message = store.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Bağlantı")
            } footer: {
                Text("Giriş Togg ID'nin resmî sayfasında yapılır; parolan bu uygulamaya verilmez. Uygulama yalnızca araç verisini okur, araca komut göndermez. Oturum Keychain'de saklanır. Bağlantı Togg'un resmî olmayan servislerini kullanır; kullanım şartları ve hesap riski sana aittir.")
            }
            Section {
                NavigationLink {
                    LogView()
                } label: {
                    Label("Günlük", systemImage: "list.bullet.rectangle")
                }
                Button("Kayıtlı geçmişi sil (\(store.history.points.count) kayıt)", systemImage: "trash", role: .destructive) {
                    store.history.clear()
                }
                .disabled(store.history.points.isEmpty)
            } header: {
                Text("Tanılama")
            } footer: {
                Text("Giriş ve veri okuma adımlarını kaydeder. Belirteç, parola, konum ve tam VIN içermez; paylaşmak güvenlidir.")
            }
            Section {
                Text("Togg Garajım")
                    .font(.footnote.weight(.semibold))
                Text("Togg / Trumore’un resmî uygulaması değildir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
