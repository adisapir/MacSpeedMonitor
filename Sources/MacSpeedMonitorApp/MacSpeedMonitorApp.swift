#if os(macOS)
import SwiftUI
import SpeedMonitorCore
import AppKit

// MARK: - App Icon View

struct AppIconView: View {
    var body: some View {
        ZStack {
            // macOS App Icon Squircle Background
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
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
func renderAppIcon() -> NSImage? {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 2.0
    return renderer.nsImage
}

@main
struct MacSpeedMonitorApp: App {
    @StateObject private var monitor = NetworkSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Render and set the dynamic Dock App Icon
        if let iconImage = renderAppIcon() {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 680, minHeight: 450)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
                    if scenePhase == .active {
                        monitor.startMonitoring()
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
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                monitor.startMonitoring()
            case .inactive, .background:
                monitor.stopMonitoring()
            @unknown default:
                monitor.stopMonitoring()
            }
        }
        .windowResizability(.contentSize)
    }
}
#endif
