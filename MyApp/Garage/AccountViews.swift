import SwiftUI

struct LiveNotificationsView: View {
    @Environment(GarageStore.self) private var store
    @State private var items: [LiveNotification] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        LiveAccountListScreen(title: "Bildirimler") {
            if let errorText {
                Text(errorText).foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView("Bildirimler okunuyor…")
            } else if items.isEmpty {
                Text("Bildirim bulunamadı.").foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            if let date = item.date {
                                Text(date.relativeText).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.symbol).foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await store.accountNotifications()
        } catch is CancellationError {
        } catch {
            errorText = "Bildirimler alınamadı. \(error.localizedDescription)"
        }
    }
}

struct LiveServiceView: View {
    @Environment(GarageStore.self) private var store
    @State private var items: [LiveServiceRecord] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        LiveAccountListScreen(title: "Servis") {
            if let errorText {
                Text(errorText).foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView("Servis kayıtları okunuyor…")
            } else if items.isEmpty {
                Text("Servis kaydı bulunamadı.").foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.place).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if let date = item.date {
                                Text(date.longDateText)
                            }
                            if let status = item.status, !status.isEmpty {
                                Text("·")
                                Text(status)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await store.serviceRecords()
        } catch is CancellationError {
        } catch {
            errorText = "Servis kayıtları alınamadı. \(error.localizedDescription)"
        }
    }
}

struct LiveSubscriptionsView: View {
    @Environment(GarageStore.self) private var store
    @State private var items: [LiveSubscription] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        LiveAccountListScreen(title: "Abonelikler") {
            if let errorText {
                Text(errorText).foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView("Abonelikler okunuyor…")
            } else if items.isEmpty {
                Text("Abonelik bulunamadı.").foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.isActive ? "Aktif" : "Pasif")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                item.isActive
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.15),
                                in: .capsule
                            )
                            .foregroundStyle(item.isActive ? Color.accentColor : .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await store.subscriptions()
        } catch is CancellationError {
        } catch {
            errorText = "Abonelikler alınamadı. \(error.localizedDescription)"
        }
    }
}

private struct LiveAccountListScreen<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        List { content }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
