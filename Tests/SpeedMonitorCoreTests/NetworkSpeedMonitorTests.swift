import XCTest
@testable import SpeedMonitorCore

@MainActor
final class NetworkSpeedMonitorTests: XCTestCase {
    func testHistoryRetentionUsesElapsedTimeAcrossLongSamplingGap() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let history = [
            SpeedHistoryPoint(timestamp: now.addingTimeInterval(-3_600), downloadSpeed: 1, uploadSpeed: 1),
            SpeedHistoryPoint(timestamp: now.addingTimeInterval(-30), downloadSpeed: 2, uploadSpeed: 2),
        ]
        let current = SpeedHistoryPoint(timestamp: now, downloadSpeed: 3, uploadSpeed: 3)

        let retained = NetworkSpeedMonitor.historyByAppending(current, to: history, duration: 60)

        XCTAssertEqual(retained, [history[1], current])
        XCTAssertLessThanOrEqual(
            retained.last!.timestamp.timeIntervalSince(retained.first!.timestamp),
            60
        )
    }

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
