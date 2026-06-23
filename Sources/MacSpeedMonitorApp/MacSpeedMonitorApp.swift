import SwiftUI
import SpeedMonitorCore
import AppKit

// MARK: - App Icon View

struct AppIconView: View {
    var body: some View {
        ZStack {
            // Keep the icon canvas transparent outside and through the outer glass layer.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.32),
                            Color.purple.opacity(0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1.5)
                )
            
            // Subtly translucent overlay card (glass layer)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(10)
            
            // Speedometer details
            VStack(spacing: 6) {
                ZStack {
                    // Gauge ring
                    Circle()
                        .trim(from: 0.15, to: 0.85)
                        .stroke(
                            Color.cyan.opacity(0.8),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [1, 3])
                        )
                        .rotationEffect(.degrees(90))
                        .frame(width: 50, height: 50)
                    
                    // Highlight arc
                    Circle()
                        .trim(from: 0.15, to: 0.55)
                        .stroke(
                            LinearGradient(
                                colors: [.cyan, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))
                        .frame(width: 50, height: 50)
                    
                    // Needle
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 3, height: 22)
                        .offset(y: -11)
                        .rotationEffect(.degrees(45))
                    
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
                
                // Active indicators
                HStack(spacing: 3) {
                    Capsule().fill(.cyan).frame(width: 2.5, height: 8)
                    Capsule().fill(.cyan).frame(width: 2.5, height: 12)
                    Capsule().fill(.cyan).frame(width: 2.5, height: 16)
                    Capsule().fill(.cyan).frame(width: 2.5, height: 12)
                    Capsule().fill(.cyan).frame(width: 2.5, height: 8)
                }
            }
        }
        .frame(width: 128, height: 128)
    }
}

@MainActor
enum AppIconProvider {
    private static var cachedIcon: NSImage?

    static func applyIcon() {
        guard let iconImage = iconImage else { return }
        NSApplication.shared.applicationIconImage = iconImage
    }

    private static var iconImage: NSImage? {
        if let cachedIcon {
            return cachedIcon
        }

        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 2.0
        guard let renderedIcon = renderer.nsImage else { return nil }
        cachedIcon = renderedIcon
        return renderedIcon
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIconProvider.applyIcon()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppIconProvider.applyIcon()
    }

    func applicationWillResignActive(_ notification: Notification) {
        AppIconProvider.applyIcon()
    }
}

@main
struct MacSpeedMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = NetworkSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("speedUnit") private var speedUnit: SpeedUnit = .bytes
    @AppStorage("showThroughputInMenuBar") private var showThroughputInMenuBar = false

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        AppIconProvider.applyIcon()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 680, minHeight: 450)
                .onAppear {
                    AppIconProvider.applyIcon()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
                    if scenePhase == .active {
                        monitor.startMonitoring()
                    }
                }
                .onChange(of: showThroughputInMenuBar) { _, isEnabled in
                    if isEnabled {
                        monitor.startMonitoring()
                    } else if scenePhase != .active {
                        monitor.stopMonitoring()
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacSpeedMonitor") {
                    NotificationCenter.default.post(name: .selectTabNotification, object: ContentView.Tab.about)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .selectTabNotification, object: ContentView.Tab.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                AppIconProvider.applyIcon()
                monitor.startMonitoring()
            case .inactive, .background:
                AppIconProvider.applyIcon()
                if !showThroughputInMenuBar {
                    monitor.stopMonitoring()
                }
            @unknown default:
                AppIconProvider.applyIcon()
                if !showThroughputInMenuBar {
                    monitor.stopMonitoring()
                }
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showThroughputInMenuBar) {
            Button("Open MacSpeedMonitor") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }

            Divider()

            Text("Upload \(formattedUploadSpeed)")
            Text("Download \(formattedDownloadSpeed)")
        } label: {
            Text("↑ \(formattedUploadSpeed) ↓ \(formattedDownloadSpeed)")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.menu)
    }

    private var formattedUploadSpeed: String {
        ThroughputFormatter.speed(monitor.uploadBytesPerSecond, unit: speedUnit)
    }

    private var formattedDownloadSpeed: String {
        ThroughputFormatter.speed(monitor.downloadBytesPerSecond, unit: speedUnit)
    }
}
