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

    private func formatBytesPerSecond(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else {
            return "0 KB/s"
        }

        let clampedValue = min(bytesPerSecond, Double(Int64.max))
        return "\(Self.speedFormatter.string(fromByteCount: Int64(clampedValue)))/s"
    }

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
