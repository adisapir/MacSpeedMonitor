import CoreLocation
import Foundation

@MainActor
public final class LocationPermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus
    @Published public private(set) var isLocationServicesEnabled: Bool
    @Published public private(set) var locationErrorDescription: String?

    private let manager = CLLocationManager()

    public override init() {
        authorizationStatus = manager.authorizationStatus
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    public var needsAuthorizationRequest: Bool {
        authorizationStatus == .notDetermined
    }

    public var canReadWiFiNames: Bool {
        guard isLocationServicesEnabled else {
            return false
        }

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
        guard isLocationServicesEnabled else {
            return "Location Services are turned off. Enable Location Services in System Settings to show Wi-Fi network names."
        }

        if let locationErrorDescription {
            return locationErrorDescription
        }

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
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
        locationErrorDescription = nil

        guard isLocationServicesEnabled else {
            return
        }

        guard needsAuthorizationRequest else {
            requestCurrentLocationIfAuthorized()
            return
        }

        manager.requestWhenInUseAuthorization()
    }

    private func requestCurrentLocationIfAuthorized() {
        guard canReadWiFiNames else {
            return
        }

        manager.requestLocation()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
            authorizationStatus = status
            locationErrorDescription = nil
            requestCurrentLocationIfAuthorized()
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationErrorDescription = nil
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationErrorDescription = "Location Services could not confirm access yet: \(error.localizedDescription)"
        }
    }
}
