import SwiftUI
import Charts
import AppKit

// MARK: - Notification Extension

extension Notification.Name {
    public static let selectTabNotification = Notification.Name("selectTabNotification")
}

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
    fileprivate static let collapsedSidebarWidth: CGFloat = 60
    fileprivate static let defaultSidebarWidth: CGFloat = 240
    fileprivate static let minimumSidebarWidth: CGFloat = 220
    fileprivate static let maximumSidebarWidth: CGFloat = 340

    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @State private var selectedTab: Tab = .home
    @State private var isSidebarCollapsed = false
    @State private var sidebarWidth = Self.defaultSidebarWidth
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var showingErrorAlert = false
    @State private var lastErrorMessage: String?
    
    public enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case networkInfo = "Connected Network"
        case wifiScan = "Wi-Fi Scan"
        case about = "About"
        case settings = "Settings"
        
        public var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .networkInfo: return "network"
            case .wifiScan: return "wifi"
            case .about: return "info.circle.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Vibrant Background for macOS
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Sidebar / Navigation Pane
                sidebarView
                
                // Content area
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .selectTabNotification)) { notification in
            if let tab = notification.object as? Tab {
                selectedTab = tab
            }
        }
        .onChange(of: monitor.lastErrorDescription) { _, newValue in
            if let desc = newValue, monitor.status == .degraded {
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
        ZStack(alignment: .trailing) {
            VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 6) {
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
                    if !isSidebarCollapsed {
                        Text("Speed Monitor")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
                .padding(.horizontal, isSidebarCollapsed ? 0 : 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Expand/Collapse Sidebar Toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: isSidebarCollapsed ? 44 : 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, isSidebarCollapsed ? 8 : 12)
                .padding(.bottom, 8)

                // Sidebar Navigation Links
                ForEach(Tab.allCases.filter { $0 != .settings }) { tab in
                    sidebarButton(for: tab)
                }

                Spacer()

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, isSidebarCollapsed ? 8 : 12)

                // Settings Button - Bottom of the pane
                sidebarButton(for: .settings)
                    .padding(.bottom, 16)
            }

            if !isSidebarCollapsed {
                SidebarResizeHandle(width: $sidebarWidth)
            }
        }
        .frame(width: isSidebarCollapsed ? Self.collapsedSidebarWidth : sidebarWidth)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
    
    private func sidebarButton(for tab: Tab) -> some View {
        SidebarButton(
            tab: tab,
            isSelected: selectedTab == tab,
            isCollapsed: isSidebarCollapsed
        ) {
            selectedTab = tab
        }
        .padding(.horizontal, isSidebarCollapsed ? 4 : 8)
    }
    
    // MARK: - Main Content Switcher
    
    private var contentView: some View {
        ZStack {
            switch selectedTab {
            case .home:
                DashboardView()
            case .networkInfo:
                NetworkInfoView()
            case .wifiScan:
                WiFiScanView()
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

private struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovered ? 0.18 : 0.08))
            .frame(width: 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }

                        let proposedWidth = (dragStartWidth ?? width) + value.translation.width
                        width = min(
                            max(proposedWidth, ContentView.minimumSidebarWidth),
                            ContentView.maximumSidebarWidth
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct SidebarButton: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCollapsed ? 0 : 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: isCollapsed ? 44 : 20, height: 32)

                if !isCollapsed {
                    Text(tab.rawValue)
                        .font(.body)
                        .fontWeight(isSelected ? .medium : .regular)
                        .lineLimit(1)
                }

                if !isCollapsed {
                    Spacer()
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .padding(.vertical, isCollapsed ? 4 : 8)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isHovered && !isSelected ? 0.12 : 0), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .shadow(color: .blue.opacity(isHovered || isSelected ? 0.16 : 0), radius: isHovered ? 8 : 4, x: 0, y: 2)
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .offset(x: isHovered && !isSelected && !isCollapsed ? 2 : 0)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .animation(.easeOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        }

        if isHovered {
            return Color.primary.opacity(0.08)
        }

        return Color.clear
    }
}

private struct RefreshButton: View {
    let title: String
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.72 : 1)
    }
}

private struct HelpItem: Identifiable {
    let term: String
    let explanation: String

    var id: String { term }
}

private struct InfoButton: View {
    let title: String
    let introduction: String
    let items: [HelpItem]

    @State private var isHovered = false
    @State private var isPinned = false

    private var isPresented: Binding<Bool> {
        Binding(
            get: { isHovered || isPinned },
            set: { isPresented in
                if !isPresented {
                    isHovered = false
                    isPinned = false
                }
            }
        )
    }

    var body: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 28)
                .background(.white.opacity(isHovered || isPinned ? 0.16 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: isPresented, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(title, systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(introduction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.term)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(item.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: 340, height: min(CGFloat(items.count * 56 + 100), 480))
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .help("About this information")
        .accessibilityLabel("About \(title)")
    }
}

// MARK: - Dashboard View (Home Tab)

struct DashboardView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @AppStorage("speedUnit") private var speedUnit: SpeedUnit = .bytes
    
    // Y-Axis dynamic scaling based on maximum values in the history
    private var chartScaleInfo: (factor: Double, label: String) {
        let maxSpeed = monitor.speedHistory.map { max($0.downloadSpeed, $0.uploadSpeed) }.max() ?? 0
        
        if speedUnit == .bits {
            let maxBits = maxSpeed * 8
            if maxBits >= 1_000_000_000 {
                return (1_000_000_000.0 / 8.0, "Gbps")
            } else if maxBits >= 1_000_000 {
                return (1_000_000.0 / 8.0, "Mbps")
            } else {
                // Minimum limit is Kbps
                return (1000.0 / 8.0, "Kbps")
            }
        } else {
            if maxSpeed >= 1024 * 1024 * 1024 {
                return (1024 * 1024 * 1024, "GB/s")
            } else if maxSpeed >= 1024 * 1024 {
                return (1024 * 1024, "MB/s")
            } else {
                // Minimum limit is KB/s
                return (1024, "KB/s")
            }
        }
    }
    
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
                    let scale = chartScaleInfo
                    
                    // Header with title + inline legend
                    HStack {
                        Text("Throughput History (in \(scale.label))")
                            .font(.headline)
                        Spacer()
                        // Inline legend — colors match the Download/Upload speed card labels
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.blue).frame(width: 8, height: 8)
                                Text("Download").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Upload").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
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
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                        } else {
                            Chart {
                                ForEach(monitor.speedHistory) { point in
                                    // Download — blue gradient fill + blue line
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Speed", point.downloadSpeed / scale.factor),
                                        series: .value("Series", "Download")
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.30), .blue.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Speed", point.downloadSpeed / scale.factor),
                                        series: .value("Series", "Download")
                                    )
                                    .foregroundStyle(Color.blue)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    .interpolationMethod(.catmullRom)
                                    
                                    // Upload — green gradient fill + green line
                                    AreaMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Speed", point.uploadSpeed / scale.factor),
                                        series: .value("Series", "Upload")
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.green.opacity(0.25), .green.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Time", point.timestamp),
                                        y: .value("Speed", point.uploadSpeed / scale.factor),
                                        series: .value("Series", "Upload")
                                    )
                                    .foregroundStyle(Color.green)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                                    AxisTick()
                                    AxisValueLabel()
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.hour().minute().second())
                                }
                            }
                            .chartLegend(.hidden) // we use the manual inline legend above
                            .frame(height: 140)
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
                            throughputStatItem(
                                title: "Download",
                                totalValue: formatBytes(monitor.totalDownloadBytes),
                                maxValue: formatSpeed(monitor.maxDownloadBytesPerSecond),
                                icon: "arrow.down.circle.fill",
                                color: .blue
                            )
                            throughputStatItem(
                                title: "Upload",
                                totalValue: formatBytes(monitor.totalUploadBytes),
                                maxValue: formatSpeed(monitor.maxUploadBytesPerSecond),
                                icon: "arrow.up.circle.fill",
                                color: .green
                            )
                            statItem(title: "Runtime", value: formatRuntime(monitor.runtime), icon: "clock.fill", color: .purple)
                        }
                    }
                }
                .padding(.horizontal)
                
                if let error = monitor.lastErrorDescription {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                } else {
                    Spacer()
                        .frame(height: 20)
                }
            }
        }
    }

    private func throughputStatItem(title: String, totalValue: String, maxValue: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    metricValue(label: "Total", value: totalValue)
                    metricValue(label: "Max", value: maxValue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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

// MARK: - Connected Network View

struct NetworkInfoView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @AppStorage("aiRecognitionPrivacyAccepted") private var aiPrivacyAccepted = false
    @State private var showingAIPrivacyDisclosure = false
    @State private var pendingAIIdentity: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with dynamic label and refresh button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network Interfaces")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Current active hardware connections")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()

                    InfoButton(
                        title: "Network Interfaces",
                        introduction: "These are the active connections your Mac can use to reach your local network or the internet.",
                        items: [
                            HelpItem(term: "Interface name", explanation: "macOS's short technical name for the connection, such as en0. Wi-Fi and Ethernet can use different names on each Mac."),
                            HelpItem(term: "IPv4 / IPv6", explanation: "The version of the network address. IPv4 addresses are shorter and familiar; IPv6 is the newer format."),
                            HelpItem(term: "IP address", explanation: "The address assigned to your Mac on this network. Right-click the card to copy it."),
                            HelpItem(term: "Link rate / speed", explanation: "The maximum connection speed currently negotiated with your router or network equipment. It is not the same as your internet speed."),
                            HelpItem(term: "Wi-Fi mode", explanation: "The Wi-Fi technology generation currently in use, such as Wi-Fi 6."),
                        ]
                    )

                    RefreshButton(title: "Refresh", isRefreshing: false) {
                        monitor.refreshInterfaces()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                if monitor.activeInterfaces.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Querying active adapters...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(monitor.activeInterfaces) { info in
                            GlassCard(glowColor: info.isUp ? .green : .gray) {
                                HStack(spacing: 16) {
                                    Image(systemName: info.wifiMode != nil ? "wifi" : "network")
                                        .font(.title)
                                        .foregroundStyle(info.isUp ? .green : .secondary)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
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
                                        
                                        // 1. IP Address
                                        if let address = info.address {
                                            HStack(spacing: 4) {
                                                Text("IP Address:")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.secondary)
                                                Text(address)
                                                    .font(.system(.subheadline, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                        
                                        // 2. Tx/Rx rates (Wireless: negotiated link rate, Wired: Link Speed)
                                        if let tx = info.txRate {
                                            HStack(spacing: 4) {
                                                Text("Link Rate:")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.secondary)
                                                Text(String(format: "%.0f Mbps", tx))
                                                    .font(.system(.subheadline, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                            }
                                        } else if let linkSpeed = info.linkSpeed {
                                            HStack(spacing: 4) {
                                                Text("Link Speed:")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.secondary)
                                                Text(linkSpeed)
                                                    .font(.system(.subheadline, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                        
                                        // 3. Wi-Fi mode (only if wireless connection)
                                        if let wifiMode = info.wifiMode {
                                            HStack(spacing: 6) {
                                                Image(systemName: "wifi")
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                                Text("Wi-Fi Mode:")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.secondary)
                                                Text(wifiMode)
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                            .contextMenu {
                                if let address = info.address {
                                    Button {
                                        copyToClipboard(address)
                                    } label: {
                                        Label("Copy IP Address", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                networkScannerSection
                    .padding(.top, 8)
            }
        }
        .onDisappear {
            monitor.cancelNetworkScan()
        }
    }

    private var networkScannerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices on Your Network")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Discover devices responding on your current local network")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                InfoButton(
                    title: "Local Network Scanner",
                    introduction: "The scanner checks only your current private IPv4 network. It sends reachability requests but does not inspect browsing activity or network payloads.",
                    items: [
                        HelpItem(term: "Privacy", explanation: "Devices with a hardware address are saved to a local Application Support file so later scans can restore details. History is never uploaded or used for analytics."),
                        HelpItem(term: "Visibility", explanation: "Firewalls, sleeping devices, guest-network isolation, and router settings can prevent devices from appearing."),
                        HelpItem(term: "Optional details", explanation: "Hostname, hardware address, manufacturer, and response time appear only when macOS and the device make them available."),
                        HelpItem(term: "Scan range", explanation: "Only the directly connected private IPv4 network is checked, with a maximum of 256 addresses. No service ports are scanned."),
                    ]
                )

                aiScanActionButton
                networkScanActionButton
            }

            if monitor.networkScanPhase == .scanning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(monitor.networkScanCompletedTargets),
                        total: Double(max(monitor.networkScanTotalTargets, 1))
                    )
                    .accessibilityLabel("Network scan progress")
                    .accessibilityValue(networkScanProgressText)

                    Text(networkScanProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(networkScanStatusText)
                    .font(.subheadline)
                    .foregroundStyle(networkScanStatusColor)
            }

            if let warning = monitor.networkScanWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if monitor.isAIRecognitionRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(monitor.aiRecognitionCompletedCount),
                        total: Double(max(monitor.aiRecognitionTotalCount, 1))
                    )
                    .accessibilityLabel("AI device recognition progress")
                    Text("Recognizing \(monitor.aiRecognitionCompletedCount) of \(monitor.aiRecognitionTotalCount) unknown devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = monitor.aiRecognitionErrorDescription {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if monitor.networkScanDevices.isEmpty {
                if monitor.networkScanPhase != .idle && monitor.networkScanPhase != .scanning {
                    Text("No responding devices were found.")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(monitor.networkScanDevices) { device in
                        NetworkDeviceRow(
                            device: device,
                            aiState: monitor.aiRecognitionStates[device.aiIdentity],
                            copyAction: copyToClipboard,
                            recognizeAction: device.isEligibleForAIRecognition
                                ? { requestAIRecognition(for: device) }
                                : nil
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .alert("Use OpenAI Device Recognition?", isPresented: $showingAIPrivacyDisclosure) {
            Button("Cancel", role: .cancel) {
                pendingAIIdentity = nil
            }
            Button("Continue") {
                aiPrivacyAccepted = true
                performPendingAIRecognition()
            }
        } message: {
            Text("Redacted device metadata—discovered hostname, vendor, role flags, and response time—will be sent to OpenAI using your API key. IP addresses and MAC addresses are never sent. AI suggestions may be inaccurate and are saved locally by MAC address for later scans.")
        }
    }

    @ViewBuilder
    private var aiScanActionButton: some View {
        if monitor.isAIRecognitionRunning {
            Button(role: .cancel) {
                monitor.cancelAIRecognition()
            } label: {
                Label("Cancel AI", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        } else if !monitor.hasOpenAIAPIKey {
            Button {
                NotificationCenter.default.post(
                    name: .selectTabNotification,
                    object: ContentView.Tab.settings
                )
            } label: {
                Label("Configure AI", systemImage: "key.fill")
            }
            .buttonStyle(.bordered)
            .disabled(monitor.networkScanPhase == .scanning)
        } else {
            Button {
                requestAIRecognition(for: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                    Text("AI Scan (\(monitor.unknownDevicesForAIRecognition.count))")
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                monitor.networkScanPhase == .scanning
                    || monitor.unknownDevicesForAIRecognition.isEmpty
            )
        }
    }

    private func requestAIRecognition(for device: DiscoveredNetworkDevice?) {
        monitor.refreshOpenAIAPIKeyAvailability()
        guard monitor.hasOpenAIAPIKey else {
            NotificationCenter.default.post(name: .selectTabNotification, object: ContentView.Tab.settings)
            return
        }
        pendingAIIdentity = device?.aiIdentity
        if aiPrivacyAccepted {
            performPendingAIRecognition()
        } else {
            showingAIPrivacyDisclosure = true
        }
    }

    private func performPendingAIRecognition() {
        if let identity = pendingAIIdentity,
           let device = monitor.networkScanDevices.first(where: { $0.aiIdentity == identity }) {
            monitor.startAIRecognition(for: device)
        } else {
            monitor.startAIRecognitionForUnknownDevices()
        }
        pendingAIIdentity = nil
    }

    @ViewBuilder
    private var networkScanActionButton: some View {
        if monitor.networkScanPhase == .scanning {
            Button(role: .cancel) {
                monitor.cancelNetworkScan()
            } label: {
                Label("Cancel Scan", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        } else {
            Button {
                monitor.startNetworkScan()
            } label: {
                Label(networkScanButtonTitle, systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var networkScanButtonTitle: String {
        switch monitor.networkScanPhase {
        case .idle: return "Scan Network"
        case .scanning: return "Cancel Scan"
        case .completed, .cancelled, .failed: return "Scan Again"
        }
    }

    private var networkScanProgressText: String {
        let count = monitor.networkScanDevices.count
        return "Scanning \(monitor.networkScanCompletedTargets) of \(monitor.networkScanTotalTargets) addresses - \(count) \(count == 1 ? "device" : "devices") found"
    }

    private var networkScanStatusText: String {
        switch monitor.networkScanPhase {
        case .idle:
            return "Run a scan when you want to check which devices respond on this network."
        case .scanning:
            return networkScanProgressText
        case .completed:
            let count = monitor.networkScanDevices.count
            let updated = monitor.lastNetworkScanAt?.formatted(date: .omitted, time: .standard) ?? "just now"
            return "\(count) \(count == 1 ? "device" : "devices") found - Updated \(updated)"
        case .cancelled:
            return "Scan cancelled. Partial results are shown."
        case .failed(let message):
            return message
        }
    }

    private var networkScanStatusColor: Color {
        switch monitor.networkScanPhase {
        case .failed: return .orange
        default: return .secondary
        }
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

private struct NetworkDeviceRow: View {
    let device: DiscoveredNetworkDevice
    let aiState: DeviceAIRecognitionState?
    let copyAction: (String) -> Void
    let recognizeAction: (() -> Void)?
    @State private var isAIInsightExpanded = false

    var body: some View {
        GlassCard(glowColor: device.isRouter ? .purple : (device.isLocalDevice ? .blue : .cyan)) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: device.isRouter ? "wifi.router.fill" : (device.isLocalDevice ? "desktopcomputer" : "network"))
                    .font(.title2)
                    .foregroundStyle(device.isStale ? Color.secondary : Color.blue)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .help(device.displayName)

                        if device.isRouter {
                            badge("Router", color: .purple)
                        }
                        if device.isLocalDevice {
                            badge("This Mac", color: .blue)
                        }
                        if device.isStale {
                            badge("Previous Scan", color: .gray)
                        }
                    }

                    Text(device.ipv4Address)
                        .font(.system(.subheadline, design: .monospaced))

                    HStack(spacing: 14) {
                        if let macAddress = device.macAddress {
                            detail("MAC", value: macAddress)
                        }
                        if let responseTime = device.responseTimeMilliseconds {
                            detail("Response", value: String(format: "%.1f ms", responseTime))
                        }
                    }

                    if let vendorName = device.vendorName {
                        detail("Vendor", value: vendorName)
                            .lineLimit(1)
                            .help(vendorName)
                    }

                    aiInsight
                }

                Spacer(minLength: 0)
            }
            .opacity(device.isStale ? 0.65 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
        }
        .contextMenu {
            Button("Copy IP Address") { copyAction(device.ipv4Address) }
            if let macAddress = device.macAddress {
                Button("Copy MAC Address") { copyAction(macAddress) }
            }
            Button("Copy All Details") { copyAction(allDetails) }
            if let recognizeAction {
                Divider()
                Button {
                    recognizeAction()
                } label: {
                    Label("Recognize Device through AI", systemImage: "sparkles")
                }
            }
        }
        .onChange(of: aiState) { _, state in
            if case .recognized = state { isAIInsightExpanded = true }
            if case .insufficient = state { isAIInsightExpanded = true }
        }
    }

    @ViewBuilder
    private var aiInsight: some View {
        if let aiState {
            Divider()
            switch aiState {
            case .analyzing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing redacted metadata with OpenAI...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .recognized(let insight):
                DisclosureGroup(isExpanded: $isAIInsightExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        aiDetail("Category", insight.category)
                        aiDetail("Likely purpose", insight.likelyPurpose)
                        aiDetail("Confidence", insight.confidence.rawValue.capitalized)
                        aiDetail("Why", insight.rationale)
                        aiDetail("Limitations", insight.limitations)
                        Text("AI suggestion—not verified")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 6)
                } label: {
                    Label(insight.suggestedName, systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                }
            case .insufficient(let reason):
                DisclosureGroup("AI could not recognize this device", isExpanded: $isAIInsightExpanded) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            case .refused(let reason):
                Label(reason, systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func aiDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func detail(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: label == "MAC" ? .monospaced : .default))
        }
        .font(.caption)
    }

    private var allDetails: String {
        var values = [device.displayName, "IP: \(device.ipv4Address)"]
        if let macAddress = device.macAddress { values.append("MAC: \(macAddress)") }
        if let vendorName = device.vendorName { values.append("Vendor: \(vendorName)") }
        if let responseTime = device.responseTimeMilliseconds {
            values.append(String(format: "Response: %.1f ms", responseTime))
        }
        return values.joined(separator: "\n")
    }

    private var accessibilityDescription: String {
        var values = [device.displayName, "IP address \(device.ipv4Address)"]
        if device.isRouter { values.append("Router") }
        if device.isLocalDevice { values.append("This Mac") }
        if device.isStale { values.append("From previous scan") }
        if let vendorName = device.vendorName { values.append("Vendor \(vendorName)") }
        if let responseTime = device.responseTimeMilliseconds {
            values.append(String(format: "Response time %.1f milliseconds", responseTime))
        }
        return values.joined(separator: ", ")
    }
}

// MARK: - Wi-Fi Scan View

struct WiFiScanView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @StateObject private var locationPermission = LocationPermissionManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wi-Fi Scan")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Nearby networks mapped by band and signal strength")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    InfoButton(
                        title: "Wi-Fi Scan Details",
                        introduction: "The scan describes nearby Wi-Fi access points. It does not read anyone's browsing activity or personal data.",
                        items: [
                            HelpItem(term: "SSID", explanation: "The Wi-Fi network name shown when you choose a network to join."),
                            HelpItem(term: "Vendor", explanation: "The likely manufacturer of the router or access point, estimated from its hardware address."),
                            HelpItem(term: "Signal", explanation: "How strongly your Mac can hear the network. A higher percentage and a dBm value closer to zero indicate a stronger signal."),
                            HelpItem(term: "Security", explanation: "The protection used by the network. WPA2 and WPA3 are common secure options; an open network has no Wi-Fi password protection."),
                            HelpItem(term: "Band", explanation: "The radio range used: 2.4 GHz reaches farther, while 5 GHz and 6 GHz can offer more speed at shorter range."),
                            HelpItem(term: "Wi-Fi generation", explanation: "The router's Wi-Fi technology family, such as Wi-Fi 5, 6, or 7."),
                            HelpItem(term: "Channel / width", explanation: "The radio lane and its size. Wider channels can carry more data but may encounter more interference."),
                            HelpItem(term: "Same / overlapping APs", explanation: "Nearby access points competing on the same or nearby channels. Higher numbers can mean more congestion."),
                            HelpItem(term: "Country", explanation: "The regulatory region announced by the access point, which controls allowed Wi-Fi channels."),
                            HelpItem(term: "BSSID", explanation: "The unique hardware address of a specific access point. It is mainly useful for technical troubleshooting."),
                        ]
                    )

                    RefreshButton(title: "Refresh", isRefreshing: monitor.isWiFiScanRefreshing) {
                        monitor.refreshWiFiScan()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        wifiLegendItem(label: "2.4 GHz", color: bandColor(.twoPointFourGHz))
                        wifiLegendItem(label: "5 GHz", color: bandColor(.fiveGHz))
                        wifiLegendItem(label: "6 GHz", color: bandColor(.sixGHz))
                        Spacer()
                        if let scanDate = monitor.lastWiFiScanAt {
                            Text("Updated \(scanDate.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard(glowColor: .cyan) {
                        WiFiRadarView(
                            networks: monitor.wifiScanResults,
                            isRefreshing: monitor.isWiFiScanRefreshing
                        )
                            .frame(height: 360)
                    }
                }
                .padding(.horizontal)

                if let guidance = locationPermission.guidanceMessage ?? monitor.wifiScanErrorDescription {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.orange)
                        Text(guidance)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal)
                }

                if monitor.wifiScanResults.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .opacity(monitor.isWiFiScanRefreshing ? 1 : 0)
                        Text(emptyWiFiScanMessage)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Networks")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(monitor.wifiScanResults) { network in
                            WiFiNetworkRow(network: network)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            locationPermission.requestAuthorizationIfNeeded()
            if locationPermission.canReadWiFiNames {
                monitor.startWiFiScanning()
            }
        }
        .onChange(of: locationPermission.canReadWiFiNames) { _, canReadWiFiNames in
            if canReadWiFiNames {
                monitor.startWiFiScanning()
            } else {
                monitor.stopWiFiScanning()
            }
        }
        .onDisappear {
            monitor.stopWiFiScanning()
        }
    }

    private var emptyWiFiScanMessage: String {
        if monitor.isWiFiScanRefreshing {
            return "Scanning nearby networks..."
        }

        if !locationPermission.canReadWiFiNames {
            return "Location Services permission is required to show Wi-Fi network names"
        }

        return "No scan results yet"
    }

    private func wifiLegendItem(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WiFiRadarView: View {
    private static let sweepDuration: TimeInterval = 2.2

    let networks: [WiFiNetworkInfo]
    let isRefreshing: Bool

    @State private var isSweepVisible = false
    @State private var sweepRotation = 0.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = max(40, size / 2 - 22)

            ZStack {
                radarBackground(center: center, radius: radius)

                if isSweepVisible {
                    radarSweep(center: center, radius: radius)
                }

                ForEach(networks) { network in
                    let point = radarPoint(for: network, center: center, radius: radius)
                    WiFiRadarDot(network: network, size: dotSize(for: network.rssi))
                        .position(point)
                }

                if networks.isEmpty {
                    Text("No networks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            updateSweep(isRefreshing: isRefreshing)
        }
        .onChange(of: isRefreshing) { _, newValue in
            updateSweep(isRefreshing: newValue)
        }
    }

    private func radarBackground(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach(1...4, id: \.self) { index in
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: radius * 2 * CGFloat(index) / 4, height: radius * 2 * CGFloat(index) / 4)
                    .position(center)
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1, height: radius * 2)
                .position(center)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: radius * 2, height: 1)
                .position(center)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.green.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
        }
    }

    private func radarSweep(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.72),
                            .init(color: .green.opacity(0.04), location: 0.80),
                            .init(color: .green.opacity(0.12), location: 0.88),
                            .init(color: .green.opacity(0.26), location: 0.96),
                            .init(color: .green.opacity(0.62), location: 1.00),
                        ],
                        center: .center
                    )
                )
                .frame(width: radius * 2, height: radius * 2)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.green.opacity(0.95), .green.opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: radius, height: 2)
                .offset(x: radius / 2)
                .shadow(color: .green.opacity(0.45), radius: 5)
        }
        .rotationEffect(.degrees(sweepRotation))
        .position(center)
        .blendMode(.screen)
        .transition(.opacity)
    }

    private func updateSweep(isRefreshing: Bool) {
        if isRefreshing {
            restartSweep()
        } else {
            stopSweep()
        }
    }

    private func restartSweep() {
        isSweepVisible = true
        sweepRotation = 0

        withAnimation(.linear(duration: Self.sweepDuration).repeatForever(autoreverses: false)) {
            sweepRotation = 360
        }
    }

    private func stopSweep() {
        withAnimation(.easeOut(duration: 0.18)) {
            isSweepVisible = false
        }
    }

    private func radarPoint(for network: WiFiNetworkInfo, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = deterministicAngle(for: network.id)
        let normalizedSignal = normalizedSignal(for: network.rssi)
        let distance = radius * (1.0 - (normalizedSignal * 0.72))
        return CGPoint(
            x: center.x + cos(angle) * distance,
            y: center.y + sin(angle) * distance
        )
    }

    private func deterministicAngle(for text: String) -> CGFloat {
        let hash = text.unicodeScalars.reduce(UInt32(2166136261)) { partial, scalar in
            (partial ^ scalar.value) &* 16777619
        }
        return CGFloat(hash % 360) * .pi / 180
    }

    private func normalizedSignal(for rssi: Int) -> CGFloat {
        let clampedRSSI = min(max(rssi, -95), -35)
        return CGFloat(clampedRSSI + 95) / 60
    }

    private func dotSize(for rssi: Int) -> CGFloat {
        8 + normalizedSignal(for: rssi) * 22
    }
}

private struct WiFiRadarDot: View {
    let network: WiFiNetworkInfo
    let size: CGFloat

    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(bandColor(network.band).opacity(network.isConnected ? 0.95 : 0.78))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(network.isConnected ? Color.yellow : .white.opacity(isHovered ? 0.5 : 0.18), lineWidth: network.isConnected ? 4 : 1)
            )
            .shadow(color: bandColor(network.band).opacity(network.isConnected ? 0.8 : 0.32), radius: isHovered ? 12 : (network.isConnected ? 12 : 5))
            .scaleEffect(isHovered ? 1.14 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $isHovered, arrowEdge: .bottom) {
                WiFiNetworkPopover(network: network)
                    .padding(12)
                    .frame(width: 260, alignment: .leading)
            }
            .accessibilityLabel("\(network.ssid), \(network.band.rawValue), \(network.rssi) dBm")
    }
}

private struct WiFiNetworkPopover: View {
    let network: WiFiNetworkInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bandColor(network.band))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(network.isConnected ? Color.yellow : .clear, lineWidth: 3)
                    )

                Text(network.ssid)
                    .font(.headline)
                    .lineLimit(2)
            }

            if network.isConnected {
                Text("Connected")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(connectedBadgeBackground)
                    .foregroundStyle(connectedBadgeForeground)
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 5) {
                wifiDetailRow("SSID", network.ssid)
                if network.isConnected,
                   let routerIPAddress = network.routerIPAddress,
                   let routerLoginURL = network.routerLoginURL {
                    Link(destination: routerLoginURL) {
                        HStack {
                            Text("Router IP")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(routerIPAddress)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Open the router login page")
                }
                wifiDetailRow("Vendor", network.vendorName)
                wifiDetailRow("Signal", "\(network.signalPercentage)% (\(network.rssi) dBm)")
                wifiDetailRow("Security", network.securityDescription)
                wifiDetailRow("Band", network.band.rawValue)
                wifiDetailRow("Wi-Fi generation", network.routerGeneration)
                wifiDetailRow("Channel", "\(network.channel)")
                wifiDetailRow("Channel width", network.channelWidth)
                wifiDetailRow("Same channel APs", "\(network.sameChannelAPCount)")
                wifiDetailRow("Overlapping APs", "\(network.overlappingChannelAPCount)")
                wifiDetailRow("Country", network.countryCode ?? "Unknown")
                wifiDetailRow("BSSID", network.bssid ?? "Unknown")
            }
        }
    }

    private func wifiDetailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

private struct WiFiNetworkRow: View {
    let network: WiFiNetworkInfo

    var body: some View {
        GlassCard(glowColor: bandColor(network.band)) {
            HStack(spacing: 12) {
                Circle()
                    .fill(bandColor(network.band))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(network.isConnected ? Color.yellow : .clear, lineWidth: 3)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(network.ssid)
                            .font(.headline)
                            .lineLimit(1)
                        if network.isConnected {
                            Text("Connected")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(connectedBadgeBackground)
                                .foregroundStyle(connectedBadgeForeground)
                                .cornerRadius(4)
                            }
                    }

                    Text("\(network.vendorName) • \(network.securityDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if network.isConnected,
                       let routerIPAddress = network.routerIPAddress,
                       let routerLoginURL = network.routerLoginURL {
                        Link(destination: routerLoginURL) {
                            HStack(spacing: 4) {
                                Text("Router: \(routerIPAddress)")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .help("Open http://\(routerIPAddress)")
                    }

                    HStack(spacing: 12) {
                        wifiRowDetail("Wi-Fi", network.routerGeneration)
                        wifiRowDetail("Band", network.band.rawValue)
                        wifiRowDetail("Channel", "\(network.channel) / \(network.channelWidth)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        wifiRowDetail("Same ch", "\(network.sameChannelAPCount)")
                        wifiRowDetail("Overlap", "\(network.overlappingChannelAPCount)")
                        wifiRowDetail("Country", network.countryCode ?? "Unknown")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    wifiRowDetail("BSSID", network.bssid ?? "Unknown")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(network.signalPercentage)%")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                    Text("\(network.rssi) dBm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button {
                copyNetworkDetails()
            } label: {
                Label("Copy Router Details", systemImage: "doc.on.doc")
            }
        }
    }

    private func wifiRowDetail(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text("\(title):")
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    private func copyNetworkDetails() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(networkDetailsText, forType: .string)
    }

    private var networkDetailsText: String {
        [
            "SSID: \(network.ssid)",
            "BSSID: \(network.bssid ?? "Unknown")",
            "Vendor/OUI: \(network.vendorName)",
            "Connected: \(network.isConnected ? "Yes" : "No")",
            "Signal: \(network.signalPercentage)% (\(network.rssi) dBm)",
            "Wi-Fi Generation: \(network.routerGeneration)",
            "Router IP: \(network.routerIPAddress ?? "Unknown")",
            "Band: \(network.band.rawValue)",
            "Channel: \(network.channel)",
            "Channel Width: \(network.channelWidth)",
            "Same Channel APs: \(network.sameChannelAPCount)",
            "Overlapping Channel APs: \(network.overlappingChannelAPCount)",
            "Country Code: \(network.countryCode ?? "Unknown")",
            "Security: \(network.securityDescription)",
        ].joined(separator: "\n")
    }
}

private let connectedBadgeBackground = Color(red: 0.0, green: 0.18, blue: 0.08)
private let connectedBadgeForeground = Color(red: 0.42, green: 1.0, blue: 0.42)

private func bandColor(_ band: WiFiNetworkInfo.Band) -> Color {
    switch band {
    case .twoPointFourGHz:
        return .orange
    case .fiveGHz:
        return .blue
    case .sixGHz:
        return .purple
    case .unknown:
        return .gray
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparklesAreVisible = false

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

                sparkle(size: 18, offset: CGSize(width: 45, height: -42), delay: 0)
                sparkle(size: 12, offset: CGSize(width: -48, height: -20), delay: 0.55)
                sparkle(size: 10, offset: CGSize(width: 42, height: 36), delay: 1.1)
            }
            .onAppear {
                guard !reduceMotion else {
                    sparklesAreVisible = true
                    return
                }

                sparklesAreVisible = true
            }
            
            VStack(spacing: 8) {
                Text("MacSpeedMonitor")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("A real-time Wi-Fi Network throughput metrics, charts, radars views and much more.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 40)
            
            VStack(spacing: 10) {
                Text("Created by Adi Sapir (github.com/adisapir)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
    }

    private func sparkle(size: CGFloat, offset: CGSize, delay: Double) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.yellow.opacity(0.9))
            .shadow(color: .yellow.opacity(0.45), radius: 5)
            .scaleEffect(sparklesAreVisible ? 1 : 0.45)
            .opacity(sparklesAreVisible ? 1 : 0.2)
            .offset(offset)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(delay),
                value: sparklesAreVisible
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject private var monitor: NetworkSpeedMonitor
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("speedUnit") private var speedUnit: SpeedUnit = .bytes
    @AppStorage("historyDurationSeconds") private var historyDurationSeconds: Int = 60
    @State private var openAIKeyInput = ""
    @State private var openAIStatusMessage: String?
    @State private var openAIStatusIsError = false
    @State private var isTestingOpenAI = false
    @State private var showingClearHistoryConfirmation = false
    
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
                    
                    // Chart history duration card
                    GlassCard(glowColor: .purple) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Throughput History", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundStyle(.purple)
                            
                            HStack {
                                Text("History Duration")
                                    .font(.body)
                                Spacer()
                                Text("\(historyDurationSeconds) seconds")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.purple)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(historyDurationSeconds) },
                                set: { historyDurationSeconds = Int($0) }
                             ), in: 30...300, step: 10)
                            
                            Text("Set the length of time (from 30 to 300 seconds) recorded in the throughput history chart.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard(glowColor: .mint) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("AI Device Recognition", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(.mint)

                            Text("Use your own OpenAI API key to get cautious AI suggestions for unknown network devices. The key is stored in macOS Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SecureField(
                                monitor.hasOpenAIAPIKey ? "Enter a replacement key" : "OpenAI API key",
                                text: $openAIKeyInput
                            )
                            .textFieldStyle(.roundedBorder)
                            .privacySensitive()

                            HStack {
                                Button(monitor.hasOpenAIAPIKey ? "Replace Key" : "Save Key") {
                                    saveOpenAIKey()
                                }
                                .disabled(openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Test Connection") {
                                    testOpenAIConnection()
                                }
                                .disabled(!monitor.hasOpenAIAPIKey || isTestingOpenAI)

                                if monitor.hasOpenAIAPIKey {
                                    Button("Remove Key", role: .destructive) {
                                        removeOpenAIKey()
                                    }
                                }

                                if isTestingOpenAI { ProgressView().controlSize(.small) }
                            }

                            Label(
                                monitor.hasOpenAIAPIKey ? "API key stored in Keychain" : "No API key configured",
                                systemImage: monitor.hasOpenAIAPIKey ? "checkmark.shield.fill" : "key"
                            )
                            .font(.caption)
                            .foregroundStyle(monitor.hasOpenAIAPIKey ? .green : .secondary)

                            if let openAIStatusMessage {
                                Text(openAIStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(openAIStatusIsError ? .orange : .green)
                            }

                            Divider()

                            HStack {
                                Label(
                                    "\(monitor.deviceHistoryRecordCount) saved device \(monitor.deviceHistoryRecordCount == 1 ? "record" : "records")",
                                    systemImage: "internaldrive"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear Device History", role: .destructive) {
                                    showingClearHistoryConfirmation = true
                                }
                                .disabled(monitor.deviceHistoryRecordCount == 0)
                            }

                            if let historyError = monitor.deviceHistoryErrorDescription {
                                Text(historyError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Text("AI recognition sends only discovered hostname, vendor, role flags, and response time. IP and MAC addresses are never sent. Scanner metadata and AI suggestions are stored locally by MAC address so later scans can restore details.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear { monitor.refreshOpenAIAPIKeyAvailability() }
        .confirmationDialog(
            "Clear all saved device history?",
            isPresented: $showingClearHistoryConfirmation
        ) {
            Button("Clear Device History", role: .destructive) {
                monitor.clearDeviceHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved scanner details and AI recognition results. Devices currently shown by an active scan remain visible.")
        }
    }

    private func saveOpenAIKey() {
        do {
            try OpenAIAPIKeyStore.shared.saveKey(openAIKeyInput)
            openAIKeyInput = ""
            openAIStatusMessage = "API key saved securely."
            openAIStatusIsError = false
            monitor.refreshOpenAIAPIKeyAvailability()
        } catch {
            openAIStatusMessage = error.localizedDescription
            openAIStatusIsError = true
        }
    }

    private func removeOpenAIKey() {
        do {
            try OpenAIAPIKeyStore.shared.removeKey()
            openAIKeyInput = ""
            openAIStatusMessage = "API key removed."
            openAIStatusIsError = false
            monitor.refreshOpenAIAPIKeyAvailability()
        } catch {
            openAIStatusMessage = error.localizedDescription
            openAIStatusIsError = true
        }
    }

    private func testOpenAIConnection() {
        isTestingOpenAI = true
        openAIStatusMessage = nil
        Task {
            do {
                try await OpenAIRecognitionProvider().testConnection()
                openAIStatusMessage = "Connected to OpenAI and confirmed gpt-5.4-mini access."
                openAIStatusIsError = false
            } catch {
                openAIStatusMessage = error.localizedDescription
                openAIStatusIsError = true
            }
            isTestingOpenAI = false
        }
    }
}
