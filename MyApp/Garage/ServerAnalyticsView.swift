import SwiftUI

/// Togg sunucusunun hesapladığı sürüş ve şarj analizleri. Bu cihazda türetilen Seyahatname'den
/// farklı olarak uygulama kapalıyken yapılan yolculukları da içerir.
struct ServerAnalyticsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case summary = "Özet"
        case journeys = "Yolculuklar"
        case charges = "Şarjlar"

        var id: String { rawValue }
    }

    @Environment(GarageStore.self) private var store
    @State private var tab = Tab.summary
    @State private var period = AnalyticsPeriod.monthly
    @State private var blocks: [ServerInsightBlock] = []
    @State private var page = ServerRecordPage(records: [], totals: ServerMetrics([:]), hasMore: false)
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Picker("Bölüm", selection: $tab) {
                    ForEach(Tab.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)

                if tab != .summary {
                    Picker("Dönem", selection: $period) {
                        Text("Haftalık").tag(AnalyticsPeriod.weekly)
                        Text("Aylık").tag(AnalyticsPeriod.monthly)
                        Text("Yıllık").tag(AnalyticsPeriod.annual)
                    }
                    .pickerStyle(.segmented)
                }

                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .glassCard()
                } else {
                    content
                }

                if (tab == .summary && !blocks.isEmpty) || (tab != .summary && !page.records.isEmpty) {
                    AIAnalyticsSummaryCard(
                        blocks: blocks,
                        records: page.records,
                        isCharge: tab == .charges
                    )
                }

                if isLoading { ProgressView() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { AppBackground() }
        .navigationTitle("Sunucu analizleri")
        .navigationBarTitleDisplayModeInline()
        .task(id: "\(tab.rawValue)-\(period.rawValue)") { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .summary:
            if blocks.isEmpty && !isLoading {
                emptyText("Bu hesap için analiz özeti henüz bulunmuyor.")
            }
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 12) {
                    Text(block.title).font(.headline)
                    metricGrid(block.metrics)
                }
                .glassCard()
            }
        case .journeys, .charges:
            if !page.records.isEmpty || page.totals != ServerMetrics([:]) {
                metricGrid(page.totals).glassCard()
            }
            if page.records.isEmpty && !isLoading {
                emptyText("Seçilen dönemde kayıt bulunamadı.")
            }
            ForEach(page.records) { record in
                recordRow(record).glassCard()
            }
            if page.hasMore {
                Button("Daha fazla kayıt") { Task { await loadMore() } }
                    .disabled(isLoading)
            }
        }
    }

    private func emptyText(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    /// Yanıtta bulunan ölçümleri iki sütunlu kutucuklar olarak gösterir.
    private func metricGrid(_ m: ServerMetrics) -> some View {
        let tiles: [(String, String, String?)] = [
            ("Mesafe", m.distanceKm.decimal(1), "km"),
            ("Yolculuk", m.journeyCount.decimal(), nil),
            ("Sürüş süresi", m.drivingHours.decimal(1), "saat"),
            ("Ort. tüketim", m.averageKWhPer100Km.decimal(1), "kWh/100 km"),
            ("Toplam tüketim", m.consumedKWh.decimal(1), "kWh"),
            ("Ekonomi puanı", m.economyScore.decimal(), "/100"),
            ("Şarj sayısı", m.chargeCount.decimal(), nil),
            ("Eklenen enerji", m.addedKWh.decimal(1), "kWh"),
        ].filter { $0.1 != "—" }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            ForEach(tiles, id: \.0) { StatTile(title: LocalizedStringKey($0.0), value: $0.1, unit: $0.2 ?? "") }
        }
    }

    private func recordRow(_ record: ServerRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.date?.shortDateTimeText ?? "Tarih yok").font(.headline)
            if tab == .charges {
                Text("%\(record.socStartPercent.decimal()) → %\(record.socEndPercent.decimal()) · \(record.addedKWh.decimal(1)) kWh")
                Text("\(record.durationMinutes.decimal()) dk").foregroundStyle(.secondary)
            } else {
                Text("\(record.distanceKm.decimal(1)) km · \(record.consumedKWh.decimal(1)) kWh")
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Yükleme

    private func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            switch tab {
            case .summary: blocks = try await store.serverInsights()
            case .journeys, .charges: page = try await store.serverRecords(isCharge: tab == .charges, period: period, offset: 0)
            }
        } catch is CancellationError {
            // Sekme ya da dönem değişince eski istek iptal olur; hata gösterilmez.
        } catch {
            errorText = "Analiz verisi alınamadı. \(error.localizedDescription)"
        }
    }

    private func loadMore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await store.serverRecords(isCharge: tab == .charges, period: period, offset: page.records.count)
            var seen = Set(page.records.map(\.id))
            page.records += next.records.filter { seen.insert($0.id).inserted }
            page.hasMore = next.hasMore
        } catch {
            errorText = "Daha fazla kayıt alınamadı. \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { ServerAnalyticsView() }.environment(GarageStore())
}
