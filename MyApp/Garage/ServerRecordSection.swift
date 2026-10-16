import SwiftUI

/// DriveExperience kayıtlarını ana ekranlarda kısa bir liste olarak gösterir.
/// Ayrıntılı filtreleme ve sayfalama ServerAnalyticsView içinde kalır.
struct ServerRecordSection: View {
    @Environment(GarageStore.self) private var store

    let isCharge: Bool
    let period: AnalyticsPeriod
    let limit: Int

    @State private var page = ServerRecordPage(records: [], totals: ServerMetrics([:]), hasMore: false)
    @State private var isLoading = false
    @State private var errorText: String?

    private var title: LocalizedStringKey {
        isCharge ? "Sunucudaki son şarjlar" : "Sunucudaki son yolculuklar"
    }

    private var icon: String {
        isCharge ? "bolt.fill" : "car.side.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title)

                Spacer()

                NavigationLink {
                    ServerAnalyticsView()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Ayrıntılı analizleri aç")
                }
            }

            if isLoading && page.records.isEmpty {
                ProgressView("Kayıtlar okunuyor…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else if let errorText, page.records.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Server kayıtları alınamadı", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .glassCard()
            } else if page.records.isEmpty {
                Text("Bu dönemde server kaydı bulunamadı.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(page.records.prefix(limit))) { record in
                        ServerRecordRow(record: record, isCharge: isCharge)
                        if record.id != page.records.prefix(limit).last?.id {
                            Divider()
                        }
                    }
                }
                .glassCard()

                if page.hasMore || page.records.count > limit {
                    NavigationLink {
                        ServerAnalyticsView()
                    } label: {
                        Text("Tüm kayıtları gör")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .task(id: "\(store.selectedVIN ?? "")-\(isCharge)-\(period.rawValue)") {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        guard store.isSignedIn, store.selectedVIN != nil else {
            page = ServerRecordPage(records: [], totals: ServerMetrics([:]), hasMore: false)
            errorText = nil
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            page = try await store.serverRecords(
                isCharge: isCharge,
                period: period,
                offset: 0
            )
        } catch is CancellationError {
            // Sekme veya araç değiştiğinde iptal edilen istek kullanıcıya hata olarak gösterilmez.
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ServerRecordRow: View {
    let record: ServerRecord
    let isCharge: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCharge ? "bolt.fill" : "car.side.fill")
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.18), in: .circle)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.date?.shortDateTimeText ?? "Tarih yok")
                    .font(.subheadline.weight(.medium))

                if isCharge {
                    Text("\(record.socStartPercent.decimal())% → \(record.socEndPercent.decimal())%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(record.distanceKm.decimal(1)) km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isCharge {
                Text(record.addedKWh.decimal(1) + " kWh")
                    .font(.subheadline.monospacedDigit())
            } else {
                Text(record.consumedKWh.decimal(1) + " kWh")
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 10)
    }
}
