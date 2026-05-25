import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @State private var showingErrorAlert = false
    @State private var lastErrorMessage: String?

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("Network Speed")
                    .font(.title2)
                    .fontWeight(.semibold)

                speedRow(title: "Download", value: monitor.downloadBytesPerSecond, color: .blue)
                speedRow(title: "Upload", value: monitor.uploadBytesPerSecond, color: .green)

                Divider()
                    .opacity(0.5)

                sessionStatsSection

                statusRow
            }
            .padding(24)
        }
        .onChange(of: monitor.lastErrorDescription) { _ in
            if let desc = monitor.lastErrorDescription, monitor.status == .degraded {
                if lastErrorMessage != desc {
                    lastErrorMessage = desc
                    showingErrorAlert = true
                }
            }
        }
        .alert("Network Error", isPresented: $showingErrorAlert) {
            Button("Dismiss", role: .cancel) { showingErrorAlert = false }
        } message: {
            Text(monitor.lastErrorDescription ?? "Unknown error.")
        }
    }

    // MARK: - Session Statistics

    private var sessionStatsSection: some View {
        VStack(spacing: 10) {
            Text("Session")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1)

            HStack(spacing: 16) {
                totalItem(
                    title: "Downloaded",
                    value: formatBytes(monitor.totalDownloadBytes),
                    icon: "arrow.down.circle",
                    color: .blue
                )

                totalItem(
                    title: "Uploaded",
                    value: formatBytes(monitor.totalUploadBytes),
                    icon: "arrow.up.circle",
                    color: .green
                )
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatRuntime(monitor.runtime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func totalItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color.opacity(0.7))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status

    private var statusRow: some View {
        VStack(spacing: 6) {
            Text("Status: \(monitor.status.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(monitor.status == .degraded ? .orange : .secondary)

            if let message = monitor.lastErrorDescription, monitor.status == .degraded {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Speed Row

    private func speedRow(title: String, value: Double, color: Color) -> some View {
        HStack {
            Label(title, systemImage: title == "Download" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(color)
                .font(.headline)

            Spacer()

            Text(formatBytesPerSecond(value))
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    // MARK: - Formatters

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else {
            return "0 KB/s"
        }

        let clampedValue = min(bytesPerSecond, Double(Int64.max))
        return "\(Self.speedFormatter.string(fromByteCount: Int64(clampedValue)))/s"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        Self.totalFormatter.string(fromByteCount: Int64(clamping: bytes))
    }

    private func formatRuntime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let totalFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
