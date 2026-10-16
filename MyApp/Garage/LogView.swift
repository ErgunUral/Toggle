import SwiftUI

/// Uygulama içi günlük ekranı. Kayıtlar en yeniden eskiye sıralanır.
struct LogView: View {
    private let logStore = LogStore.shared
    @State private var category: LogCategory?
    @State private var showsDebug = true
    @State private var showsDiagnosis = false

    private var entries: [LogEntry] {
        logStore.entries.reversed().filter { entry in
            (category == nil || entry.category == category) && (showsDebug || entry.level != .debug)
        }
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("Kayıt yok", systemImage: "text.alignleft")
                    .listRowBackground(Color.clear)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.date.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))))
                            .monospacedDigit()
                        Text(entry.level.rawValue).fontWeight(.semibold).foregroundStyle(color(for: entry.level))
                        Text(entry.category.rawValue)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Günlük")
        .navigationBarTitleDisplayModeInline()
        .sheet(isPresented: $showsDiagnosis) {
            LogDiagnosisView(entries: logStore.entries)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Açıkla", systemImage: "sparkles") { showsDiagnosis = true }
                    .disabled(logStore.entries.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: logStore.exportText) {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
                .disabled(logStore.entries.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Filtre", systemImage: "line.3.horizontal.decrease.circle") {
                    Picker("Kategori", selection: $category) {
                        Text("Tümü").tag(LogCategory?.none)
                        ForEach(LogCategory.allCases) { Text($0.rawValue).tag(LogCategory?.some($0)) }
                    }
                    Toggle("Ayrıntılı (debug) kayıtlar", isOn: $showsDebug)
                    Button("Günlüğü temizle", systemImage: "trash", role: .destructive) { logStore.clear() }
                }
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}

#Preview {
    NavigationStack { LogView() }
}
