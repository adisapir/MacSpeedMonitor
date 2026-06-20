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
    public let signalPercentage: Int
    public let band: Band
    public let channel: Int
    public let channelWidth: String
    public let isConnected: Bool
    public let securityDescription: String
    public let routerGeneration: String
    public let routerIPAddress: String?
    public let vendorName: String
    public let sameChannelAPCount: Int
    public let overlappingChannelAPCount: Int
    public let countryCode: String?

    public init(
        ssid: String,
        bssid: String?,
        rssi: Int,
        signalPercentage: Int,
        band: Band,
        channel: Int,
        channelWidth: String,
        isConnected: Bool,
        securityDescription: String,
        routerGeneration: String,
        routerIPAddress: String? = nil,
        vendorName: String,
        sameChannelAPCount: Int = 0,
        overlappingChannelAPCount: Int = 0,
        countryCode: String?
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.signalPercentage = signalPercentage
        self.band = band
        self.channel = channel
        self.channelWidth = channelWidth
        self.isConnected = isConnected
        self.securityDescription = securityDescription
        self.routerGeneration = routerGeneration
        self.routerIPAddress = routerIPAddress
        self.vendorName = vendorName
        self.sameChannelAPCount = sameChannelAPCount
        self.overlappingChannelAPCount = overlappingChannelAPCount
        self.countryCode = countryCode
    }

    public func withCongestionDetails(sameChannelAPCount: Int, overlappingChannelAPCount: Int) -> WiFiNetworkInfo {
        WiFiNetworkInfo(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            signalPercentage: signalPercentage,
            band: band,
            channel: channel,
            channelWidth: channelWidth,
            isConnected: isConnected,
            securityDescription: securityDescription,
            routerGeneration: routerGeneration,
            routerIPAddress: routerIPAddress,
            vendorName: vendorName,
            sameChannelAPCount: sameChannelAPCount,
            overlappingChannelAPCount: overlappingChannelAPCount,
            countryCode: countryCode
        )
    }

    public var routerLoginURL: URL? {
        guard let routerIPAddress, !routerIPAddress.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = routerIPAddress
        return components.url
    }
}
