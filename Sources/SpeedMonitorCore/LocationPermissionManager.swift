import CoreLocation
import Foundation

@MainActor
public final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    public override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    public var needsAuthorizationRequest: Bool {
        authorizationStatus == .notDetermined
    }

    public var canReadWiFiNames: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    public var guidanceMessage: String? {
        switch authorizationStatus {
        case .notDetermined:
            return "Location permission is required for macOS to reveal Wi-Fi network names."
        case .restricted:
            return "Location Services are restricted, so macOS may hide Wi-Fi network names."
        case .denied:
            return "Location permission is denied. Enable it in System Settings to show Wi-Fi network names."
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        @unknown default:
            return "Location permission status is unknown, so macOS may hide Wi-Fi network names."
        }
    }

    public func requestAuthorizationIfNeeded() {
        guard needsAuthorizationRequest else {
            return
        }

        manager.requestWhenInUseAuthorization()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
        }
    }
}
