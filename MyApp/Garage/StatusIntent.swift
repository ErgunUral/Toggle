import AppIntents

/// "Arabamın şarjı ne kadar?" Siri, Kısayollar ve Spotlight'tan çalışır.
/// Yalnızca okur; araca komut göndermez.
nonisolated struct VehicleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Araç durumu"
    static let description = IntentDescription("Bataryayı, menzili ve şarj durumunu okur. Araca komut göndermez.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppLog.info(.app, "Siri/Kısayol: araç durumu istendi")
        let service = TogglService.shared
        guard await service.isSignedIn else {
            AppLog.warning(.app, "Siri/Kısayol: oturum yok")
            throw AppIntentError.UserActionRequired.signin
        }

        let state: VehicleState
        do {
            guard let vehicle = try await service.vehicles().first else {
                throw VehicleStatusError.noVehicle
            }
            state = try await service.state(for: vehicle)
        } catch ServiceError.sessionExpired {
            throw AppIntentError.UserActionRequired.signin
        } catch let error as VehicleStatusError {
            throw error
        } catch {
            AppLog.error(.app, "Siri/Kısayol: veri alınamadı: \(AppLog.describe(error))")
            throw VehicleStatusError.unavailable
        }

        guard let battery = state.battery else {
            return .result(dialog: "Batarya bilgisi okunamadı.")
        }
        let percent = Int(battery.rounded())
        let isCharging = state.isCharging ?? false

        switch (state.range, isCharging) {
        case let (range?, true):
            return .result(dialog: "Batarya yüzde \(percent), menzil \(Int(range.rounded())) kilometre. Şu an şarj oluyor.")
        case let (range?, false):
            return .result(dialog: "Batarya yüzde \(percent), menzil \(Int(range.rounded())) kilometre.")
        case (nil, true):
            return .result(dialog: "Batarya yüzde \(percent). Şu an şarj oluyor.")
        case (nil, false):
            return .result(dialog: "Batarya yüzde \(percent).")
        }
    }

}

/// Ortak: oturumu ve ilk aracı çözer, klima komutunu bulut üzerinden gönderir.
nonisolated private func sendClimate(enabled: Bool, temperature: Double) async throws {
    let service = TogglService.shared
    guard await service.isSignedIn else {
        throw AppIntentError.UserActionRequired.signin
    }
    do {
        guard let vehicle = try await service.vehicles().first else {
            throw VehicleStatusError.noVehicle
        }
        _ = try await service.sendClimateCommand(vin: vehicle.vin, enabled: enabled, temperature: temperature)
    } catch ServiceError.sessionExpired {
        throw AppIntentError.UserActionRequired.signin
    } catch let error as VehicleStatusError {
        throw error
    } catch let error as ClimateCommandError {
        AppLog.warning(.app, "Siri/Kısayol: klima komutu sonucu: \(error)")
        throw error
    } catch {
        AppLog.error(.app, "Siri/Kısayol: klima komutu başarısız: \(AppLog.describe(error))")
        throw VehicleStatusError.commandFailed
    }
}

/// "Klimayı çalıştır" — araca komut gönderir, bu yüzden önce onay ister.
nonisolated struct StartClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Klimayı çalıştır"
    static let description = IntentDescription("Aracın klimasını seçtiğin sıcaklıkta çalıştırır.")

    @Parameter(title: "Sıcaklık (°C)", default: 22)
    var temperature: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Klimayı \(\.$temperature) °C'ye ayarla")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (16...30).contains(temperature) else {
            throw VehicleStatusError.invalidTemperature
        }
        try await requestConfirmation(result: .result(dialog: "Klima \(temperature) derecede çalıştırılsın mı?"))
        AppLog.info(.app, "Siri/Kısayol: klima çalıştırılıyor (\(temperature)°C)")
        // Geri alınamaz iş en sona bırakılır; perform() yeniden denenebilir.
        try await sendClimate(enabled: true, temperature: Double(temperature))
        return .result(dialog: "Klima \(temperature) derecede çalıştırıldı.")
    }
}

/// "Klimayı kapat" — araca komut gönderir, bu yüzden önce onay ister.
nonisolated struct StopClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Klimayı kapat"
    static let description = IntentDescription("Aracın klimasını kapatır.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(result: .result(dialog: "Klima kapatılsın mı?"))
        AppLog.info(.app, "Siri/Kısayol: klima kapatılıyor")
        try await sendClimate(enabled: false, temperature: 22)
        return .result(dialog: "Klima kapatıldı.")
    }
}

nonisolated enum VehicleStatusError: Error, CustomLocalizedStringResourceConvertible {
    case noVehicle
    case unavailable
    case commandFailed
    case invalidTemperature

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .commandFailed: "Komut araca gönderilemedi. Biraz sonra tekrar dene."
        case .invalidTemperature: "Sıcaklık 16–30°C arasında olmalı."
        case .noVehicle: "Hesabında araç bulunamadı."
        case .unavailable: "Araç verisi şu an alınamadı. Biraz sonra tekrar dene."
        }
    }
}

nonisolated struct GarageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: VehicleStatusIntent(),
            phrases: [
                "\(.applicationName) şarjım ne kadar",
                "\(.applicationName) araç durumu",
            ],
            shortTitle: "Araç durumu",
            systemImageName: "car.side.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "\(.applicationName) klimayı çalıştır",
                "\(.applicationName) aracı ısıt",
            ],
            shortTitle: "Klimayı çalıştır",
            systemImageName: "fan.fill"
        )
        AppShortcut(
            intent: StopClimateIntent(),
            phrases: [
                "\(.applicationName) klimayı kapat",
            ],
            shortTitle: "Klimayı kapat",
            systemImageName: "fan.slash.fill"
        )
    }
}
