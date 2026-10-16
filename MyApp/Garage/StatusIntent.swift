import AppIntents

/// "Arabamın şarjı ne kadar?" Siri, Kısayollar ve Spotlight'tan çalışır.
/// Yalnızca okur; araca komut göndermez.
nonisolated struct VehicleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Araç durumu"
    static let description = IntentDescription("Bataryayı, menzili ve şarj durumunu okur. Araca komut göndermez.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppLog.info(.app, "Siri/Kısayol: araç durumu istendi")
        let service = TogglService()
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
        let isCharging = state.chargeMode.map(Self.isCharging) ?? false

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

    /// Uygulamadaki şarj modu deseniyle aynıdır.
    private static func isCharging(_ mode: String) -> Bool {
        mode.range(
            of: "^(CHRGMODE_CHARGE|(CHARGEMODE_)?(AC_CHARGING|DC_CHARGING|CHARGING_AC|CHARGING_DC|CHARGING))$",
            options: .regularExpression
        ) != nil
    }
}

nonisolated enum VehicleStatusError: Error, CustomLocalizedStringResourceConvertible {
    case noVehicle
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
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
    }
}
