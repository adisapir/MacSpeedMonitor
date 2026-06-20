import XCTest
@testable import SpeedMonitorCore

@MainActor
final class NetworkSpeedMonitorTests: XCTestCase {
    func testMonitoringTimerAdvancesDashboardRuntime() async throws {
        let monitor = NetworkSpeedMonitor(samplingInterval: 0.2)

        monitor.startMonitoring()
        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(monitor.status, .running)
        XCTAssertGreaterThan(monitor.runtime, 0)
        XCTAssertNotNil(monitor.lastUpdatedAt)

        monitor.stopMonitoring()
        XCTAssertEqual(monitor.status, .stopped)
    }
}
