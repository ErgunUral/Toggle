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
                    if store.isSignedIn {
                        NavigationLink { LiveServiceView() } label: {
                            row("Servis", "Canlı bakım kayıtları", "wrench.and.screwdriver.fill")
                        }
                        NavigationLink { LiveSubscriptionsView() } label: {
                            row("Abonelikler", "Canlı bağlantı ve hizmet paketleri", "bag.fill")
                        }
                    } else if !store.snapshot.isLive {
                        NavigationLink { ServiceView() } label: {
                            row("Servis", "Örnek bakım kayıtları", "wrench.and.screwdriver.fill")
                        }
                        NavigationLink { SubscriptionsView() } label: {
                            row("Abonelikler", "Örnek bağlantı ve hizmet paketleri", "bag.fill")
                        }
                    }
                }
                Section {
                    if store.isSignedIn {
                        NavigationLink { LiveNotificationsView() } label: {
                            row("Bildirimler", "Canlı araç bildirimleri", "bell.fill")
                        }
                    } else if !store.snapshot.isLive {
                        NavigationLink { NotificationsView() } label: {
                            row("Bildirimler", "Örnek araç uyarıları", "bell.fill")
                        }
                    }
                    NavigationLink { SpecsView() } label: {
                        row("Teknik bilgiler", "\(store.snapshot.model) · \(store.snapshot.edition)", "info.circle.fill")
                    }
                    NavigationLink { SettingsView() } label: {
                        row("Ayarlar", "Bağlantı ve görünüm", "gearshape.fill")
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
    @State private var bluetooth = BLEGarageManager()
    @State private var digitalKeyStore = DigitalKeyStore()

    var body: some View {
        ListScreen(title: "Dijital anahtar") {
            Section {
                LabeledContent("Durum", value: bluetooth.state.title)

                if let name = bluetooth.discoveredName {
                    LabeledContent("Bulunan araç", value: name)
                }

                if let rssi = bluetooth.discoveredRSSI {
                    LabeledContent("Sinyal", value: "\(rssi) dBm")
                }

                if bluetooth.state == .connected {
                    Button("Bağlantıyı kes", systemImage: "bolt.horizontal.circle") {
                        bluetooth.disconnect()
                    }
                } else if bluetooth.discoveredName != nil {
                    Button("Araca bağlan", systemImage: "link") {
                        bluetooth.connectToDiscoveredVehicle()
                    }
                } else {
                    Button("Araç ara", systemImage: "antenna.radiowaves.left.and.right") {
                        bluetooth.startScan()
                    }
                }

                if !bluetooth.discoveredCharacteristics.isEmpty {
                    Text("\(bluetooth.discoveredCharacteristics.count) BLE karakteristiği keşfedildi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("BLE bağlantısı")
            } footer: {
                Text("Bu sürüm yalnızca BLE servisini keşfeder ve bağlantı durumunu gösterir; araç komutu göndermez.")
            }

            Section {
                LabeledContent(
                    "Yerel anahtar",
                    value: digitalKeyStore.hasLocalKey ? "Hazır" : "Oluşturulmadı"
                )

                if digitalKeyStore.hasLocalKey {
                    Button("Yerel anahtarı sil", systemImage: "trash", role: .destructive) {
                        digitalKeyStore.deleteLocalKey()
                    }
                } else {
                    Button("Güvenli anahtar çifti oluştur", systemImage: "key") {
                        digitalKeyStore.createKeyIfNeeded()
                    }
                }

                if let errorMessage = digitalKeyStore.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Dijital anahtar hazırlığı")
            } footer: {
                Text("Anahtar cihazın Secure Enclave’inde tutulur. Araç sertifikası, VIN eşleştirmesi ve BLE komutları henüz etkin değildir.")
            }

            Section {
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
            } footer: {
                Text("Kayıtlı araç anahtarları örnek veridir.")
            }
        }
    }
}

private struct SpecsView: View {
    @Environment(GarageStore.self) private var store

    private func ownerText(_ type: String?) -> String {
        switch type {
        case "Private": "Bireysel"
        case let other?: other
        case nil: "—"
        }
    }

    private func keySharingText(_ enabled: Bool?) -> String {
        switch enabled {
        case true: "Açık"
        case false: "Kapalı"
        case nil: "—"
        }
    }

    var body: some View {
        let snapshot = store.snapshot
        ListScreen(title: "Teknik bilgiler") {
            if snapshot.isLive {
                Section {
                    LabeledContent("Model", value: snapshot.model)
                    LabeledContent("Versiyon", value: snapshot.edition.isEmpty ? "—" : snapshot.edition)
                    LabeledContent("Model yılı", value: String(snapshot.year))
                    LabeledContent("Üretici", value: snapshot.manufacturer ?? "—")
                    LabeledContent("Plaka", value: snapshot.plate ?? "—")
                    LabeledContent("VIN", value: snapshot.vin)
                    LabeledContent("Yazılım sürümü", value: snapshot.softwareVersion ?? "—")
                    LabeledContent("Sahiplik", value: ownerText(snapshot.ownerType))
                    LabeledContent("Anahtar paylaşımı", value: keySharingText(snapshot.keySharingEnabled))
                } header: {
                    Text("Aracım · canlı")
                } footer: {
                    Text("Yazılım sürümünün araca mı yoksa servise mi ait olduğu doğrulanmadı.")
                }
            } else {
                ForEach(SampleData.specs, id: \.0) { spec in
                    LabeledContent(spec.0, value: spec.1)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(GarageStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webSession
    @AppStorage("theme") private var themeRaw = AppTheme.system.rawValue
    @AppStorage(GarageStore.climateDefaultKey) private var climateDefault = 22

    var body: some View {
        ListScreen(title: "Ayarlar") {
            Section("Görünüm") {
                Picker("Tema", selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            // Klima yalnızca örnek modda kullanılabildiğinden ayar da orada gösterilir.
            if !store.snapshot.isLive {
                Section {
                    Picker("Klima açılış derecesi", selection: $climateDefault) {
                        ForEach(Array(GarageStore.climateTemperatureRange), id: \.self) { Text("\($0)°C").tag($0) }
                    }
                } footer: {
                    Text("Klima açılırken bu derece kullanılır.")
                }
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
