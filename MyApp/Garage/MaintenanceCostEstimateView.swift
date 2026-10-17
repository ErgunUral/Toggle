import SwiftUI

struct MaintenanceCostEstimateView: View {
    @AppStorage("maintenanceCostService") private var serviceCost = 12_000.0
    @AppStorage("maintenanceCostTires") private var tireCost = 0.0
    @AppStorage("maintenanceCostAuxBattery") private var auxBatteryCost = 6_000.0
    @AppStorage("maintenanceCostBrakes") private var brakeCost = 15_000.0

    private var total: Double {
        serviceCost + tireCost + auxBatteryCost + brakeCost
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Periyodik bakım") {
                    moneyField(value: $serviceCost)
                }
                LabeledContent("Lastik seti") {
                    moneyField(value: $tireCost)
                }
                LabeledContent("12 V akü") {
                    moneyField(value: $auxBatteryCost)
                }
                LabeledContent("Fren sistemi") {
                    moneyField(value: $brakeCost)
                }
            } header: {
                Text("Tahmini kalemler")
            } footer: {
                Text("Tutarları kendi servis tekliflerine göre güncelleyebilirsin.")
            }

            Section {
                HStack {
                    Label("Toplam tahmin", systemImage: "turkishlirasign.circle")
                        .font(.headline)
                    Spacer()
                    Text(total, format: .currency(code: "TRY"))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }

            Section {
                Label("Bu değerler resmi servis fiyatı değildir.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Gerçek maliyet; parça, işçilik, servis, kampanya ve aracın durumuna göre değişebilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Bakım maliyeti")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moneyField(value: Binding<Double>) -> some View {
        TextField("₺", value: value, format: .number)
            .multilineTextAlignment(.trailing)
            .frame(width: 110)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
}
