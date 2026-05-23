#if os(macOS)
import SwiftUI
import SpeedMonitorCore
import AppKit

@main
struct MacSpeedMonitorApp: App {
    @StateObject private var monitor = NetworkSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Set a custom icon in the Dock since swift run doesn't use an app bundle
        if let iconImage = NSImage(systemSymbolName: "network", accessibilityDescription: "Speed Monitor") {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 320, minHeight: 180)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
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
        .windowResizability(.contentSize)
    }
}
#endif

