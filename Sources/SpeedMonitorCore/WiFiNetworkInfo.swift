import Foundation

public struct WiFiNetworkInfo: Identifiable, Hashable, Sendable {
    public enum Band: String, Sendable {
        case twoPointFourGHz = "2.4 GHz"
        case fiveGHz = "5 GHz"
        case sixGHz = "6 GHz"
        case unknown = "Unknown"
    }

    public var id: String {
        bssid ?? "\(ssid)-\(channel)-\(rssi)"
    }

    public let ssid: String
    public let bssid: String?
    public let rssi: Int
    public let band: Band
    public let channel: Int
    public let isConnected: Bool
    public let securityDescription: String

    public init(
        ssid: String,
        bssid: String?,
        rssi: Int,
        band: Band,
        channel: Int,
        isConnected: Bool,
        securityDescription: String
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.band = band
        self.channel = channel
        self.isConnected = isConnected
        self.securityDescription = securityDescription
    }
}
