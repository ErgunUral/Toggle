import SwiftUI

struct SoftwareVersionView: View {
    @Environment(GarageStore.self) private var store

    private var versions: [HistoryPoint] {
        store.history.points
            .filter { $0.softwareVersion != nil }
            .sorted { $0.date > $1.date }
    }

    private var hasChanged: Bool {
        Set(versions.compactMap(\.softwareVersion)).count > 1
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Mevcut sürüm", value: store.snapshot.softwareVersion ?? "—")

                    if hasChanged {
                        Label("Sürüm geçmişte değişmiş", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Kayıtlı değişiklik yok", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Canlı araç bilgisi")
                } footer: {
                    Text("Bu kontrol yalnızca uygulamanın gördüğü canlı sürüm değişikliklerini izler. Resmî güncelleme uygunluğu kontrolü yapmaz.")
                }

                Section("Sürüm kayıtları") {
                    if versions.isEmpty {
                        Text("Canlı yazılım sürümü kaydı bulunmuyor.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(versions) { point in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.softwareVersion ?? "—")
                                        .font(.subheadline.weight(.semibold))
                                    Text(point.date, format: .dateTime.day().month().year().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if point.id == versions.first?.id {
                                    Text("Güncel")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Yazılım sürümü")
            .navigationBarTitleDisplayModeInline()
        }
    }
}
