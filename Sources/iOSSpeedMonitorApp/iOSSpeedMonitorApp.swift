import SwiftUI
import SpeedMonitorCore

#if os(iOS)
@main
struct iOSSpeedMonitorApp: App {
    @StateObject private var monitor = NetworkSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .padding(.vertical, 8)
                .task {
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
    }
}
#endif

