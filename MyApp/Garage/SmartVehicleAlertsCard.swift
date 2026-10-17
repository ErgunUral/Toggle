import SwiftUI

struct SmartVehicleAlertsCard: View {
    let snapshot: VehicleSnapshot
    var showsEmptyState = false

    private var alerts: [SmartVehicleAlert] {
        var result: [SmartVehicleAlert] = []

        if snapshot.brakeWarning == true {
            result.append(SmartVehicleAlert(
                title: "Fren sistemi uyarısı",
                detail: "Fren uyarısı etkin. Güvenli bir yerde durup servise başvurun.",
                severity: .critical
            ))
        }

        if snapshot.engineWarning == true {
            result.append(SmartVehicleAlert(
                title: "Araç sistemi uyarısı",
                detail: "Motor/aktarma uyarısı etkin. Yetkili servis kontrolü önerilir.",
                severity: .warning
            ))
        }

        if let battery = snapshot.battery, battery <= 0.20 {
            result.append(SmartVehicleAlert(
                title: "Batarya seviyesi düşük",
                detail: "Çekiş bataryası %\( (battery * 100).decimal() ) seviyesinde.",
                severity: .warning
            ))
        }

        if AuxBattery.isLow(snapshot.auxBattery) {
            result.append(SmartVehicleAlert(
                title: "12 V akü seviyesi düşük",
                detail: "12 V akü değerini kontrol ettirmeniz önerilir.",
                severity: .warning
            ))
        }

        let tireValues = [
            snapshot.tires.frontLeft,
            snapshot.tires.frontRight,
            snapshot.tires.rearLeft,
            snapshot.tires.rearRight
        ].compactMap { $0 }
        if let minimum = tireValues.min(), minimum < 31 {
            result.append(SmartVehicleAlert(
                title: "Lastik basıncı düşük",
                detail: "En düşük ölçüm \(minimum.decimal(1)) PSI.",
                severity: .warning
            ))
        }

        if let updatedAt = snapshot.updatedAt, Date.now.timeIntervalSince(updatedAt) > 30 * 60 {
            result.append(SmartVehicleAlert(
                title: "Veri güncel değil",
                detail: "Araç telemetrisi 30 dakikadan uzun süredir yenilenmedi.",
                severity: .info
            ))
        }

        return result
    }

    var body: some View {
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Akıllı bildirimler", systemImage: "bell.badge.fill")
                    .font(.headline)

                ForEach(alerts) { alert in
                    SmartVehicleAlertRow(alert: alert)
                }

                Text("Uyarılar mevcut telemetriye göre oluşturulur; kesin servis teşhisi değildir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        } else if showsEmptyState {
            Label("Aktif uyarı yok", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
    }
}

private struct SmartVehicleAlertRow: View {
    let alert: SmartVehicleAlert

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.callout.weight(.semibold))
                Text(alert.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: alert.severity.symbol)
                .foregroundStyle(alert.severity.color)
        }
    }
}

private struct SmartVehicleAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity

    enum Severity {
        case critical
        case warning
        case info

        var symbol: String {
            switch self {
            case .critical: "exclamationmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .critical: .red
            case .warning: .orange
            case .info: .secondary
            }
        }
    }
}
