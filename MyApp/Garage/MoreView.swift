import SwiftUI
import Charts
import AuthenticationServices

struct MoreView: View {
    @Environment(GarageStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PremiumGarageHeader(
                        name: store.snapshot.name,
                        model: store.snapshot.model,
                        imageName: store.color.imageName
                    )

                    PremiumVehicleStatus(
                        isSignedIn: store.isSignedIn,
                        isLive: store.snapshot.isLive,
                        updatedAt: store.snapshot.updatedAt
                    )

                    BrandSectionHeader(
                        "Hızlı erişim",
                        detail: "GARAGE CONTROL"
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        NavigationLink { AIGarageAssistantView() } label: {
                            PremiumMenuTile(
                                title: "AI asistan",
                                subtitle: "Sor ve keşfet",
                                symbol: "sparkles",
                                tint: ToggGarageBrand.turquoise
                            )
                        }

                        if store.isSignedIn && store.snapshot.isLive {
                            NavigationLink { DigitalKeyView() } label: {
                                PremiumMenuTile(
                                    title: "Dijital anahtar",
                                    subtitle: "Araç kontrolleri",
                                    symbol: "key.fill",
                                    tint: ToggGarageBrand.signal
                                )
                            }
                        } else {
                            NavigationLink { SettingsView() } label: {
                                PremiumMenuTile(
                                    title: "Bağlantı",
                                    subtitle: "Hesabı bağla",
                                    symbol: "link",
                                    tint: ToggGarageBrand.electric
                                )
                            }
                        }

                        if store.isSignedIn {
                            NavigationLink { LiveNotificationsView() } label: {
                                PremiumMenuTile(
                                    title: "Bildirimler",
                                    subtitle: "Uyarılar ve durum",
                                    symbol: "bell.fill",
                                    tint: ToggGarageBrand.electric
                                )
                            }
                        } else {
                            NavigationLink { NotificationsView() } label: {
                                PremiumMenuTile(
                                    title: "Bildirimler",
                                    subtitle: "Uyarılar ve durum",
                                    symbol: "bell.fill",
                                    tint: ToggGarageBrand.electric
                                )
                            }
                        }

                        NavigationLink { SettingsView() } label: {
                            PremiumMenuTile(
                                title: "Ayarlar",
                                subtitle: "Tercihler",
                                symbol: "gearshape.fill",
                                tint: .secondary
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    PremiumMenuGroup(title: "Araç merkezi", symbol: "car.side.fill") {
                        NavigationLink { SpecsView() } label: {
                            PremiumMenuRow(
                                title: "Teknik bilgiler",
                                detail: "\(store.snapshot.model) · \(store.snapshot.edition)",
                                symbol: "info.circle.fill"
                            )
                        }
                        NavigationLink { SoftwareVersionView() } label: {
                            PremiumMenuRow(
                                title: "Yazılım sürümü",
                                detail: "Araç yazılımını ve güncellemeleri takip et",
                                symbol: "arrow.triangle.2.circlepath"
                            )
                        }
                    }

                    PremiumMenuGroup(title: "Yaşam ve bakım", symbol: "wrench.and.screwdriver.fill") {
                        NavigationLink { MaintenancePlannerView() } label: {
                            PremiumMenuRow(
                                title: "Bakım planı",
                                detail: "Servis ve bakım takibini yönet",
                                symbol: "calendar.badge.clock"
                            )
                        }
                        NavigationLink { MaintenanceCostEstimateView() } label: {
                            PremiumMenuRow(
                                title: "Bakım maliyeti",
                                detail: "Kişisel maliyet tahmini",
                                symbol: "turkishlirasign.circle"
                            )
                        }
                        NavigationLink { JourneyView() } label: {
                            PremiumMenuRow(
                                title: "Seyahatname",
                                detail: "Sürüş geçmişini ve tüketimi incele",
                                symbol: "safari"
                            )
                        }
                        NavigationLink { MonthlyVehicleReportView() } label: {
                            PremiumMenuRow(
                                title: "Aylık rapor",
                                detail: "Kullanım ve enerji özetini gör",
                                symbol: "chart.bar.fill"
                            )
                        }
                        NavigationLink { AuxHistoryView() } label: {
                            PremiumMenuRow(
                                title: "12 V akü geçmişi",
                                detail: "Yardımcı akü ölçümlerini ve düşük eşiklerini gör",
                                symbol: "battery.25percent"
                            )
                        }
                        NavigationLink { DriveModeAnalysisView() } label: {
                            PremiumMenuRow(
                                title: "Sürüş modu analizi",
                                detail: "Comfort, Eco ve diğer modların dağılımını incele",
                                symbol: "speedometer"
                            )
                        }
                        NavigationLink { LocationHistoryView() } label: {
                            PremiumMenuRow(
                                title: "Konum geçmişi",
                                detail: "Kaydedilen araç konumlarını haritada incele",
                                symbol: "map.fill"
                            )
                        }
                    }

                    NavigationLink { ThemeView() } label: {
                        HStack {
                            Label("Görünüm", systemImage: "paintpalette.fill")
                            Spacer()
                            Text("Tema ve renkler")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(.thinMaterial, in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background { AppBackground() }
            .navigationTitle("Menü")
        }
    }

    private struct PremiumGarageHeader: View {
        let name: String
        let model: String
        let imageName: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Garajım")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ToggGarageBrand.turquoise)

                        Text(name)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))

                        Text(model)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    BrandMark(size: 48)
                }

                VehicleImageView(name: imageName)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(model) görseli")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToggGarageBrand.darkGradient, in: .rect(cornerRadius: 28))
            .foregroundStyle(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(ToggGarageBrand.turquoiseLight.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private struct PremiumVehicleStatus: View {
        let isSignedIn: Bool
        let isLive: Bool
        let updatedAt: Date?

        var body: some View {
            HStack(spacing: 10) {
                Circle()
                    .fill(isLive ? .green : .secondary)
                    .frame(width: 9, height: 9)

                Text(isLive ? "Araç bağlantısı aktif" : "Araç çevrimdışı")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(isSignedIn ? "Hesap bağlı" : "Demo")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if let updatedAt {
                    Text("· \(updatedAt.relativeText)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private struct PremiumMenuTile: View {
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 2)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .padding(15)
            .background(.thinMaterial, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private struct PremiumMenuGroup<Content: View>: View {
        let title: LocalizedStringKey
        let symbol: String
        @ViewBuilder let content: () -> Content

        init(
            title: LocalizedStringKey,
            symbol: String,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.symbol = symbol
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.headline.weight(.bold))

                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .rect(cornerRadius: 22))
            }
        }
    }

    private struct PremiumMenuRow: View {
        let title: String
        let detail: String
        let symbol: String

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .frame(width: 25)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
    }

    private struct MenuIdentityCard: View {
        let vehicleName: String
        let model: String
        let vin: String
        let isSignedIn: Bool
        let isLive: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BrandMark(size: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicleName)
                            .font(.headline)

                        Text("\(model) · \(vin)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    MenuStatusPill(
                        title: isSignedIn ? "Hesap bağlı" : "Demo hesap",
                        symbol: isSignedIn ? "person.crop.circle.fill" : "person.crop.circle",
                        tint: isSignedIn ? .green : .secondary
                    )

                    MenuStatusPill(
                        title: isLive ? "Canlı araç" : "Çevrimdışı",
                        symbol: isLive
                            ? "antenna.radiowaves.left.and.right"
                            : "icloud.slash",
                        tint: isLive ? .green : .secondary
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        ToggGarageBrand.turquoise.opacity(0.16),
                        ToggGarageBrand.electric.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 22)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(ToggGarageBrand.turquoise.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private struct MenuStatusPill: View {
        let title: String
        let symbol: String
        let tint: Color

        var body: some View {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(tint.opacity(0.10), in: .capsule)
        }
    }

    private struct MoreSection<Content: View>: View {
        let title: LocalizedStringKey
        @ViewBuilder let content: () -> Content

        init(
            title: LocalizedStringKey,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .rect(cornerRadius: 22))
            }
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

struct DigitalKeyView: View {
    @Environment(GarageStore.self) private var store
    @State private var bluetooth = BLEGarageManager()
    @State private var digitalKeyStore = DigitalKeyStore()
    @State private var isLoadingCertificate = false
    @State private var isSendingCommand = false
    @State private var commandMessage: String?
    @AppStorage("proximityUnlockEnabled") private var proximityUnlockEnabled = false
    @State private var proximityUnlockCompleted = false
    @State private var proximityUnlockInProgress = false
    @State private var proximityUnlockMessage: String?

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
                Text("Araç BLE servisi keşfedilir. Güvenli anahtar ve araç doğrulaması tamamlandığında komut gönderilebilir.")
            }

            Section("Yaklaşınca açılma") {
                Toggle("Yaklaşınca kapıları aç", isOn: $proximityUnlockEnabled)

                Text("Açıkken yalnızca doğrulanmış dijital anahtar, bağlı BLE aracı ve yakın sinyal algılandığında bir kez kilit açma komutu gönderilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let proximityUnlockMessage {
                    Text(proximityUnlockMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if proximityUnlockEnabled, let rssi = bluetooth.discoveredRSSI {
                    LabeledContent("Sinyal", value: "\(rssi) dBm")
                }
            }

            if bluetooth.state == .connected,
               digitalKeyStore.certificateVIN == store.selectedVIN,
               digitalKeyStore.vehiclePublicKey != nil {
                Section("Araç komutları") {
                    commandButton("Kapıları aç", command: .unlock)
                    commandButton("Kapıları kilitle", command: .lock)
                    commandButton("Bagajı aç", command: .trunkOpen)
                    commandButton("Bagajı kapat", command: .trunkClose)
                    commandButton("Camları aç", command: .windowsOpen)
                    commandButton("Camları kapat", command: .windowsClose)
                    commandButton("Sürüşü yetkilendir", command: .driveAuthorize)

                    if let commandMessage {
                        Text(commandMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

                    if let associatedVIN = digitalKeyStore.associatedVIN {
                        LabeledContent("İlişkili VIN", value: associatedVIN)
                        Button("VIN ilişkisini kaldır", systemImage: "link.badge.plus") {
                            digitalKeyStore.removeAssociation()
                        }
                    } else if let selectedVIN = store.selectedVIN {
                        Button("Seçili araçla ilişkilendir", systemImage: "link") {
                            digitalKeyStore.associate(with: selectedVIN)
                        }
                    } else {
                        Text("VIN ilişkisi için önce canlı araç seçilmelidir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Güvenli anahtar çifti oluştur", systemImage: "key") {
                        digitalKeyStore.createKeyIfNeeded()
                    }
                }

                if let selectedVIN = store.selectedVIN, digitalKeyStore.hasLocalKey {
                    Button {
                        Task {
                            isLoadingCertificate = true
                            defer { isLoadingCertificate = false }
                            do {
                                guard let publicKey = digitalKeyStore.publicKeyBase64 else {
                                    throw DigitalKeyStoreError.keyReadFailed
                                }
                                let response = try await store.digitalCertificate(phonePublicKey: publicKey)
                                digitalKeyStore.installCertificate(response, for: selectedVIN)
                            } catch {
                                AppLog.error(.auth, "Dijital anahtar sertifikası alınamadı: \(AppLog.describe(error))")
                            }
                        }
                    } label: {
                        if isLoadingCertificate {
                            Label("Sertifika alınıyor…", systemImage: "hourglass")
                        } else {
                            Label(
                                digitalKeyStore.certificateVIN == selectedVIN
                                    ? "Sertifikayı yenile"
                                    : "Araç sertifikasını al",
                                systemImage: "checkmark.seal"
                            )
                        }
                    }
                    .disabled(isLoadingCertificate)
                }

                if let certificateVIN = digitalKeyStore.certificateVIN {
                    LabeledContent("Sertifika VIN", value: certificateVIN)
                    if digitalKeyStore.vehiclePublicKey == nil {
                        Text("Sunucu araç doğrulama anahtarını döndürmedi; BLE komutları doğrulama tamamlanana kadar kapalıdır.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("Anahtar Secure Enclave’de, sertifika Keychain’de tutulur. Araç doğrulama anahtarı ve BLE bağlantısı hazır olduğunda komut gönderilebilir.")
            }

        }
        .onAppear {
            if proximityUnlockEnabled {
                proximityUnlockCompleted = false
                proximityUnlockMessage = nil
                bluetooth.startScan()
            }
        }
        .onChange(of: proximityUnlockEnabled, initial: false) { _, enabled in
            proximityUnlockCompleted = false
            proximityUnlockMessage = nil
            if enabled {
                bluetooth.startScan()
            } else {
                bluetooth.stopScan()
            }
        }
        .onChange(of: bluetooth.state, initial: true) { _, _ in
            Task { await attemptProximityUnlock() }
        }
        .onChange(of: bluetooth.discoveredRSSI, initial: false) { _, rssi in
            // Araç yakında bulunduysa kullanıcıdan "Araca bağlan"a basmasını beklemeden bağlanır;
            // kilit komutu yine yalnızca bağlantı ve anahtar doğrulamasından sonra gönderilir.
            if proximityUnlockEnabled,
               !proximityUnlockCompleted,
               bluetooth.state == .idle,
               bluetooth.discoveredName != nil,
               let rssi, rssi >= -65 {
                bluetooth.connectToDiscoveredVehicle()
            }
            Task { await attemptProximityUnlock() }
        }
    }

    private func attemptProximityUnlock() async {
        guard proximityUnlockEnabled,
              !proximityUnlockCompleted,
              !proximityUnlockInProgress,
              let rssi = bluetooth.discoveredRSSI,
              rssi >= -65,
              bluetooth.state == .connected,
              digitalKeyStore.certificateVIN == store.selectedVIN,
              digitalKeyStore.vehiclePublicKey != nil else {
            return
        }

        proximityUnlockInProgress = true
        defer { proximityUnlockInProgress = false }

        do {
            _ = try await bluetooth.sendToggCommand(.unlock, using: digitalKeyStore)
            proximityUnlockCompleted = true
            proximityUnlockMessage = "Yakın araç algılandı; kapılar açıldı."
            AppLog.info(.app, "BLE: yaklaşınca açılma komutu başarıyla gönderildi")
        } catch {
            proximityUnlockMessage = "Yaklaşınca açılma başarısız: \(error.localizedDescription)"
            AppLog.error(.app, "BLE yaklaşınca açılma başarısız: \(AppLog.describe(error))")
        }
    }

    private func commandButton(_ title: String, command: ToggBLEProtocol.Command) -> some View {
        Button {
            Task {
                isSendingCommand = true
                commandMessage = nil
                defer { isSendingCommand = false }

                do {
                    _ = try await bluetooth.sendToggCommand(command, using: digitalKeyStore)
                    commandMessage = "Komut araç tarafından kabul edildi."
                } catch {
                    commandMessage = error.localizedDescription
                    AppLog.error(.app, "BLE komutu başarısız: \(AppLog.describe(error))")
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: commandIcon(for: command))
                Spacer()
                if isSendingCommand {
                    ProgressView()
                }
            }
        }
        .disabled(isSendingCommand)
    }

    private func commandIcon(for command: ToggBLEProtocol.Command) -> String {
        switch command {
        case .unlock: "lock.open"
        case .lock: "lock.fill"
        case .trunkOpen: "car.rear.and.tire.marks"
        case .trunkClose: "car.rear"
        case .windowsOpen: "arrow.up"
        case .windowsClose: "arrow.down"
        case .driveAuthorize: "key.fill"
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
    @AppStorage(GarageStore.climateDefaultKey) private var climateDefault = 22

    var body: some View {
        ListScreen(title: "Ayarlar") {
            Section("Görünüm") {
                Picker(
                    "Araç rengi",
                    selection: Binding(
                        get: { store.color },
                        set: { store.setManualColor($0) }
                    )
                ) {
                    ForEach(VehicleColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }

                if store.isColorManual {
                    Button("API rengini kullan", systemImage: "arrow.triangle.2.circlepath") {
                        store.useVehicleColorFromAPI()
                        Task { await store.refresh() }
                    }
                }
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
