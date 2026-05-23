import SwiftUI
import SpeedMonitorCore
#if os(macOS)
import AppKit
#endif

@main
struct MacSpeedMonitorApp: App {
    @StateObject private var monitor = NetworkSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
#if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Set a custom icon in the Dock since swift run doesn't use an app bundle
        if let iconImage = NSImage(systemSymbolName: "network", accessibilityDescription: "Speed Monitor") {
            NSApplication.shared.applicationIconImage = iconImage
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 320, minHeight: 180)
                .onAppear {
#if os(macOS)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
#endif
                    if scenePhase == .active {
                        monitor.startMonitoring()
                    }
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
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}

