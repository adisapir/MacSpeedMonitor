import SwiftUI
import WidgetKit

private enum SharedSnapshot {
    static let appGroup = "group.com.adisapir.MacSpeedMonitor"
    static let downloadKey = "widget.downloadBytesPerSecond"
    static let uploadKey = "widget.uploadBytesPerSecond"
    static let updatedAtKey = "widget.updatedAt"
    static let isRunningKey = "widget.isRunning"

    static func load() -> (download: Double, upload: Double, updatedAt: Date?, isRunning: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return (0, 0, nil, false)
        }

        let timestamp = defaults.double(forKey: updatedAtKey)
        return (
            max(0, defaults.double(forKey: downloadKey)),
            max(0, defaults.double(forKey: uploadKey)),
            timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil,
            defaults.bool(forKey: isRunningKey)
        )
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpeedEntry {
        SpeedEntry(date: .now, configuration: ConfigurationAppIntent(),
                   downloadBytesPerSecond: 24_700_000, uploadBytesPerSecond: 5_800_000,
                   updatedAt: .now, isRunning: true)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SpeedEntry {
        entry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SpeedEntry> {
        let now = Date()
        let current = entry(configuration: configuration, date: now)
        var entries = [current]

        if current.isRunning, let updatedAt = current.updatedAt {
            let staleDate = updatedAt.addingTimeInterval(120)
            if staleDate > now {
                entries.append(SpeedEntry(
                    date: staleDate,
                    configuration: configuration,
                    downloadBytesPerSecond: current.downloadBytesPerSecond,
                    uploadBytesPerSecond: current.uploadBytesPerSecond,
                    updatedAt: updatedAt,
                    isRunning: current.isRunning
                ))
            }
        }

        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60)))
    }

    private func entry(configuration: ConfigurationAppIntent, date: Date = .now) -> SpeedEntry {
        let snapshot = SharedSnapshot.load()
        return SpeedEntry(date: date, configuration: configuration,
                          downloadBytesPerSecond: snapshot.download,
                          uploadBytesPerSecond: snapshot.upload,
                          updatedAt: snapshot.updatedAt, isRunning: snapshot.isRunning)
    }
}

struct SpeedEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let updatedAt: Date?
    let isRunning: Bool
}

struct WiFiPulseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpeedEntry

    private var isFresh: Bool {
        guard entry.isRunning, let updatedAt = entry.updatedAt else { return false }
        return entry.date.timeIntervalSince(updatedAt) < 120
    }

    var body: some View {
        Group {
            if family == .systemSmall { compactLayout } else { wideLayout }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.10), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            speedRow(title: "Download", icon: "arrow.down.circle.fill", color: .blue,
                     value: entry.downloadBytesPerSecond)
            Divider().opacity(0.35)
            speedRow(title: "Upload", icon: "arrow.up.circle.fill", color: .green,
                     value: entry.uploadBytesPerSecond)
            Spacer(minLength: 0)
            freshnessLabel
        }
    }

    private var wideLayout: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 18 : 12) {
            header
            HStack(spacing: 12) {
                speedCard(title: "Download", icon: "arrow.down.circle.fill", color: .blue,
                          value: entry.downloadBytesPerSecond)
                speedCard(title: "Upload", icon: "arrow.up.circle.fill", color: .green,
                          value: entry.uploadBytesPerSecond)
            }
            if family == .systemLarge {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Network throughput", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Text("Open WiFiPulse for the live chart, session totals, and network details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            freshnessLabel
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.needle.fill").foregroundStyle(.blue.gradient)
            Text("WiFiPulse").font(.headline).fontWeight(.bold)
            Spacer()
            Circle().fill(isFresh ? Color.green : Color.orange).frame(width: 7, height: 7)
                .accessibilityLabel(isFresh ? "Live" : "Not updating")
        }
    }

    private func speedRow(title: String, icon: String, color: Color, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption).fontWeight(.semibold).foregroundStyle(color)
            Text(formatSpeed(value)).font(.system(.headline, design: .monospaced, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.65)
        }
    }

    private func speedCard(title: String, icon: String, color: Color, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
            Text(formatSpeed(value))
                .font(.system(size: family == .systemLarge ? 27 : 22, weight: .bold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.16)) }
    }

    private var freshnessLabel: some View {
        Group {
            if let updatedAt = entry.updatedAt {
                Text(isFresh ? "Updated \(updatedAt, style: .relative)" : "Last update \(updatedAt, style: .relative)")
            } else {
                Text("Open WiFiPulse to begin monitoring")
            }
        }
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if entry.configuration.unit == .bits {
            let bits = bytesPerSecond * 8
            if bits >= 1_000_000_000 { return String(format: "%.2f Gbps", bits / 1_000_000_000) }
            if bits >= 1_000_000 { return String(format: "%.2f Mbps", bits / 1_000_000) }
            if bits >= 1_000 { return String(format: "%.2f Kbps", bits / 1_000) }
            return String(format: "%.0f bps", bits)
        }

        let clamped = min(max(0, bytesPerSecond), Double(Int64.max))
        return "\(Self.byteFormatter.string(fromByteCount: Int64(clamped)))/s"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

struct WiFiPulseWidget: Widget {
    let kind = "WiFiPulseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            WiFiPulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Network Speed")
        .description("See the latest download and upload speeds measured by WiFiPulse.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
