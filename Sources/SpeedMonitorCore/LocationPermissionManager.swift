import CoreLocation
import Foundation
import Network

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

@MainActor
public final class LocalNetworkPermissionManager: ObservableObject {
    public enum AuthorizationState: Equatable {
        case notRequested
        case requesting
        case granted
        case denied
        case unavailable(String)
    }

    @Published public private(set) var authorizationState: AuthorizationState = .notRequested

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "MacSpeedMonitor.LocalNetworkPermission")

    public init() {}

    public var guidanceMessage: String? {
        switch authorizationState {
        case .denied:
            return "Local Network access is denied. Enable it for MacSpeedMonitor in System Settings to discover devices."
        case .unavailable(let message):
            return "Local Network access could not be confirmed: \(message)"
        case .notRequested, .requesting, .granted:
            return nil
        }
    }

    public func requestAuthorizationIfNeeded() {
        guard browser == nil, authorizationState != .granted else { return }

        authorizationState = .requesting
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_wifipulse._tcp", domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor in
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .ready:
                    self.authorizationState = .granted
                    self.finishRequest(browser)
                case .waiting(let error):
                    if Self.isLocalNetworkPolicyDenied(error) {
                        self.authorizationState = .denied
                        self.finishRequest(browser)
                    }
                case .failed(let error):
                    self.authorizationState = Self.isLocalNetworkPolicyDenied(error)
                        ? .denied
                        : .unavailable(error.localizedDescription)
                    self.finishRequest(browser)
                case .setup:
                    break
                case .cancelled:
                    if self.authorizationState == .requesting {
                        self.authorizationState = .notRequested
                    }
                @unknown default:
                    break
                }
            }
        }
        browser.start(queue: queue)
    }

    public func cancelRequest() {
        guard let browser else { return }
        finishRequest(browser)
    }

    private func finishRequest(_ browser: NWBrowser) {
        browser.cancel()
        if self.browser === browser {
            self.browser = nil
        }
    }

    private static func isLocalNetworkPolicyDenied(_ error: NWError) -> Bool {
        guard case .dns(let code) = error else { return false }
        // Network.framework reports kDNSServiceErr_PolicyDenied for denied local-network access.
        return code == -65_570
    }
}
