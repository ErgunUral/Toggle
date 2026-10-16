import SwiftUI
import WidgetKit

struct GarageWidgetEntry: TimelineEntry {
    let date: Date
    let vehicleName: String
    let batteryPercent: Int
    let rangeKm: Int
    let isLive: Bool
}

struct GarageWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GarageWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.com.ibrahim.togggaraj")
        return GarageWidgetEntry(
            date: .now,
            vehicleName: defaults?.string(forKey: "widget.vehicleName") ?? "T10X’İM",
            batteryPercent: defaults?.object(forKey: "widget.batteryPercent") as? Int ?? 78,
            rangeKm: defaults?.object(forKey: "widget.rangeKm") as? Int ?? 365,
            isLive: defaults?.bool(forKey: "widget.isLive") ?? false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GarageWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GarageWidgetEntry>) -> Void) {
        let entry = placeholder(in: context)
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct GarageWidgetEntryView: View {
    let entry: GarageWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "car.fill")
                    .foregroundStyle(.tint)
                Text("Togg Garajım")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle()
                    .fill(entry.isLive ? .green : .secondary)
                    .frame(width: 7, height: 7)
            }

            Text(entry.vehicleName)
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.batteryPercent)%")
                    .font(.title2.weight(.bold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(entry.rangeKm) km")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(entry.isLive ? "Canlı veri" : "Örnek veri")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct GarageWidget: Widget {
    let kind = "GarageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GarageWidgetProvider()) { entry in
            GarageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Togg Garajım")
        .description("Araç bataryası ve menzil özetini gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    GarageWidget()
} timeline: {
    GarageWidgetEntry(
        date: .now,
        vehicleName: "T10X’İM",
        batteryPercent: 78,
        rangeKm: 365,
        isLive: false
    )
}
