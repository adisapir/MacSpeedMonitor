import Foundation

public struct NetworkInterfaceInfo: Identifiable, Hashable {
    public var id: String {
        return "\(name)-\(family)-\(address ?? "")"
    }
    public let name: String
    public let family: String
    public let address: String?
    public let isUp: Bool
    public let isRunning: Bool
    public let isLoopback: Bool
    public let linkSpeed: String?
    public let txRate: Double?
    public let rxRate: Double?
    public let wifiMode: String?

    public init(name: String, family: String, address: String?, isUp: Bool, isRunning: Bool, isLoopback: Bool, linkSpeed: String?, txRate: Double?, rxRate: Double?, wifiMode: String?) {
        self.name = name
        self.family = family
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
        self.linkSpeed = linkSpeed
        self.txRate = txRate
        self.rxRate = rxRate
        self.wifiMode = wifiMode
    }
}
