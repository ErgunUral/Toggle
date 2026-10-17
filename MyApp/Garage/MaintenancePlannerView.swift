import SwiftUI

struct MaintenancePlannerView: View {
    @Environment(GarageStore.self) private var store
    @AppStorage("maintenanceNextDate") private var savedNextDate = 0.0
    @State private var nextServiceDate = Date.now

    private var snapshot: VehicleSnapshot { store.snapshot }

    private var serviceOdometerText: String {
        guard let odometer = snapshot.odometer else { return "Kilometre verisi yok" }
        let next = ceil((odometer + 1) / 10_000) * 10_000
        let remaining = max(0, next - odometer)
        return "Sonraki bakım: \(Int(next)) km · \(Int(remaining)) km kaldı"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bakım planı", systemImage: "wrench.and.screwdriver.fill")
                        .font(.headline)
                    Text(serviceOdometerText)
                        .font(.subheadline)
                    Text("Kilometre tahmini yerel araç verisine göre hesaplanır; resmi servis planı değildir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Sonraki bakım tarihi", systemImage: "calendar")
                        .font(.headline)
                    DatePicker(
                        "Tarih",
                        selection: $nextServiceDate,
                        in: Date.now...,
                        displayedComponents: .date
                    )
                    .onChange(of: nextServiceDate) {
                        savedNextDate = nextServiceDate.timeIntervalSince1970
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                maintenanceRow(
                    title: "12 V akü",
                    detail: AuxBattery.isLow(snapshot.auxBattery) ? "Kontrol öneriliyor" : "Şimdilik normal",
                    symbol: "minus.plus.batteryblock",
                    isWarning: AuxBattery.isLow(snapshot.auxBattery)
                )
                maintenanceRow(
                    title: "Lastik basıncı",
                    detail: tireStatus,
                    symbol: "gauge.with.dots.needle.33percent",
                    isWarning: tireWarning
                )
                maintenanceRow(
                    title: "Fren ve araç sistemi",
                    detail: warningStatus,
                    symbol: "exclamationmark.triangle",
                    isWarning: snapshot.brakeWarning == true || snapshot.engineWarning == true
                )

                Text("Bu planlayıcı yalnızca kişisel takip içindir; güvenlik uyarılarında yetkili servise başvurun.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Bakım planı")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if savedNextDate > 0 {
                nextServiceDate = Date(timeIntervalSince1970: savedNextDate)
            }
        }
    }

    private var tireWarning: Bool {
        [
            snapshot.tires.frontLeft,
            snapshot.tires.frontRight,
            snapshot.tires.rearLeft,
            snapshot.tires.rearRight
        ]
        .compactMap { $0 }
        .contains { $0 < 31 }
    }

    private var tireStatus: String {
        guard let minimum = [
            snapshot.tires.frontLeft,
            snapshot.tires.frontRight,
            snapshot.tires.rearLeft,
            snapshot.tires.rearRight
        ]
        .compactMap({ $0 })
        .min() else {
            return "Ölçüm yok"
        }
        return tireWarning ? "Düşük basınç: \(minimum.decimal(1)) PSI" : "Normal · en düşük \(minimum.decimal(1)) PSI"
    }

    private var warningStatus: String {
        if snapshot.brakeWarning == true || snapshot.engineWarning == true {
            return "Aktif araç uyarısı var"
        }
        if snapshot.brakeWarning == nil || snapshot.engineWarning == nil {
            return "Uyarı bilgisi eksik"
        }
        return "Aktif uyarı yok"
    }

    private func maintenanceRow(
        title: LocalizedStringKey,
        detail: String,
        symbol: String,
        isWarning: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isWarning ? .orange : .green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isWarning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isWarning ? .orange : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
