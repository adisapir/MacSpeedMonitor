import SwiftUI
import Charts

// MARK: - Enums & Models

public enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Match System Settings"
    case light = "Light"
    case dark = "Dark"
    
    public var id: String { self.rawValue }
    
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum SpeedUnit: String, CaseIterable, Identifiable {
    case bytes = "Bytes/s (MB/s)"
    case bits = "Bits/s (Mbps)"
    
    public var id: String { self.rawValue }
}

// MARK: - Visual Effect View for macOS Translucency

#if os(macOS)
import AppKit
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#else
struct VisualEffectView: View {
    var body: some View {
        Color.clear
    }
}
#endif

// MARK: - Glassmorphic Card View

struct GlassCard<Content: View>: View {
    var content: Content
    var glowColor: Color
    @State private var isHovered = false
    
    init(glowColor: Color = .blue, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.glowColor = glowColor
    }
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: glowColor.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 12 : 8, x: 0, y: 4)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - ContentView Shell

public struct ContentView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @State private var selectedTab: Tab = .home
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var showingErrorAlert = false
    @State private var lastErrorMessage: String?
    
    public enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case networkInfo = "Network information"
        case about = "About"
        case settings = "Settings"
        
        public var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .networkInfo: return "network"
            case .about: return "info.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            #if os(macOS)
            // Vibrant Background for macOS
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            #endif
            
            HStack(spacing: 0) {
                // Sidebar / Navigation Pane
                sidebarView
                
                // Content area
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .onChange(of: monitor.lastErrorDescription) { newError in
            if let desc = newError, monitor.status == .degraded {
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
    
    // MARK: - Sidebar Layout (Left window navigation pane)
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title or Header Area
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Speed Monitor")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Sidebar Navigation Links
            ForEach(Tab.allCases.filter { $0 != .settings }) { tab in
                sidebarButton(for: tab)
            }
            
            Spacer()
            
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 12)
            
            // Settings Button - Bottom of the pane, visually distinct
            sidebarButton(for: .settings, isSettings: true)
                .padding(.bottom, 16)
        }
        .frame(width: 200)
        #if os(macOS)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        #else
        .background(Color(.systemGroupedBackground))
        #endif
    }
    
    private func sidebarButton(for tab: Tab, isSettings: Bool = false) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? .white : (isSettings ? .orange : .blue))
                
                Text(tab.rawValue)
                    .font(.body)
                    .fontWeight(selectedTab == tab ? .medium : .regular)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(selectedTab == tab ? .white : .primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Main Content Switcher
    
    private var contentView: some View {
        ZStack {
            switch selectedTab {
            case .home:
                DashboardView()
            case .networkInfo:
                NetworkInfoView()
            case .about:
                AboutView()
            case .settings:
                SettingsView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }
}

// MARK: - Dashboard View (Home Tab)

struct DashboardView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @AppStorage("speedUnit") private var speedUnit: SpeedUnit = .bytes
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title Area
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Speed Dashboard")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Real-time network throughput and statistics")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                // Speed Cards
                HStack(spacing: 16) {
                    // Download Card
                    GlassCard(glowColor: .blue) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Download", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.blue)
                                Spacer()
                                Circle()
                                    .fill(monitor.status == .running ? .green : .orange)
                                    .frame(width: 8, height: 8)
                            }
                            
                            Text(formatSpeed(monitor.downloadBytesPerSecond))
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .contentTransition(.numericText())
                                .minimumScaleFactor(0.5)
                        }
                    }
                    
                    // Upload Card
                    GlassCard(glowColor: .green) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Upload", systemImage: "arrow.up.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Spacer()
                                Circle()
                                    .fill(monitor.status == .running ? .green : .orange)
                                    .frame(width: 8, height: 8)
                            }
                            
                            Text(formatSpeed(monitor.uploadBytesPerSecond))
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .contentTransition(.numericText())
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Real-time chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Throughput History")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    GlassCard(glowColor: .purple) {
                        if monitor.speedHistory.isEmpty {
                            VStack {
                                Spacer()
                                Text("No throughput data yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                        } else {
                            Chart {
                                ForEach(monitor.speedHistory) { point in
                                    // Download Area
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Download", point.downloadSpeed)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.25), .blue.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Download", point.downloadSpeed)
                                    )
                                    .foregroundStyle(.blue)
                                    .interpolationMethod(.catmullRom)
                                    
                                    // Upload Area
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Upload", point.uploadSpeed)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.green.opacity(0.2), .green.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Upload", point.uploadSpeed)
                                    )
                                    .foregroundStyle(.green)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Session stats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Statistics")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    GlassCard(glowColor: .blue) {
                        HStack(spacing: 24) {
                            statItem(title: "Downloaded", value: formatBytes(monitor.totalDownloadBytes), icon: "arrow.down.circle.fill", color: .blue)
                            statItem(title: "Uploaded", value: formatBytes(monitor.totalUploadBytes), icon: "arrow.up.circle.fill", color: .green)
                            statItem(title: "Runtime", value: formatRuntime(monitor.runtime), icon: "clock.fill", color: .purple)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Monitor status row
                HStack {
                    Text("Status: \(monitor.status.rawValue.capitalized)")
                        .font(.footnote)
                        .foregroundStyle(monitor.status == .degraded ? .orange : .secondary)
                    Spacer()
                    if let error = monitor.lastErrorDescription {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Formatters
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else {
            return speedUnit == .bytes ? "0 KB/s" : "0 Kbps"
        }
        
        if speedUnit == .bits {
            let bitsPerSecond = bytesPerSecond * 8
            if bitsPerSecond >= 1_000_000_000 {
                return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000.0)
            } else if bitsPerSecond >= 1_000_000 {
                return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000.0)
            } else if bitsPerSecond >= 1000 {
                return String(format: "%.2f Kbps", bitsPerSecond / 1000.0)
            } else {
                return String(format: "%.0f bps", bitsPerSecond)
            }
        } else {
            let clampedValue = min(bytesPerSecond, Double(Int64.max))
            return "\(Self.speedFormatter.string(fromByteCount: Int64(clampedValue)))/s"
        }
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

// MARK: - Network Information View

struct NetworkInfoView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @State private var interfaces: [NetworkInterfaceInfo] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Interfaces")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Current active hardware and software addresses")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                if interfaces.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Querying network adapters...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(interfaces) { info in
                            GlassCard(glowColor: info.isUp ? .green : .gray) {
                                HStack(spacing: 16) {
                                    Image(systemName: info.isLoopback ? "arrow.counterclockwise.circle.fill" : "network")
                                        .font(.title)
                                        .foregroundStyle(info.isUp ? .green : .secondary)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(info.name)
                                                .font(.headline)
                                            Spacer()
                                            
                                            // Badges
                                            Text(info.family)
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundStyle(.blue)
                                                .cornerRadius(4)
                                        }
                                        
                                        if let address = info.address {
                                            Text("IP: \(address)")
                                                .font(.system(.subheadline, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        HStack(spacing: 12) {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(info.isUp ? .green : .red)
                                                    .frame(width: 6, height: 6)
                                                Text(info.isUp ? "Up" : "Down")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(info.isRunning ? .green : .red)
                                                    .frame(width: 6, height: 6)
                                                Text(info.isRunning ? "Running" : "Idle")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            if info.isLoopback {
                                                Text("Loopback")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            interfaces = monitor.getNetworkInterfaces()
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Dynamic Logo drawing
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                
                // Speed gauge representation
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(90))
                
                Circle()
                    .trim(from: 0.15, to: 0.6)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(90))
                
                // Speedneedle
                Capsule()
                    .fill(.orange)
                    .frame(width: 4, height: 32)
                    .offset(y: -16)
                    .rotationEffect(.degrees(35))
                
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            }
            
            VStack(spacing: 8) {
                Text("MacSpeedMonitor")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("A beautiful, lightweight, modern macOS network speed monitor written entirely in SwiftUI. Features real-time throughput metrics, historical chart view, and interface address tracking.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 40)
            
            VStack(spacing: 10) {
                Text("Made with Liquid Glass design principles.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("speedUnit") private var speedUnit: SpeedUnit = .bytes
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure appearance and display units")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                VStack(spacing: 16) {
                    // Appearance card
                    GlassCard(glowColor: .orange) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Appearance", systemImage: "paintbrush.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            
                            Picker("Theme", selection: $appTheme) {
                                ForEach(AppTheme.allCases) { theme in
                                    Text(theme.rawValue).tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Text("Select whether the app should always match system appearance, or stick to Light or Dark mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Measurement unit card
                    GlassCard(glowColor: .blue) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Data Unit", systemImage: "chart.bar.doc.horizontal.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            
                            Picker("Unit Selection", selection: $speedUnit) {
                                ForEach(SpeedUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Text("Bytes/s is standard for transfers, while Bits/s (Mbps) matches internet provider speeds.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
