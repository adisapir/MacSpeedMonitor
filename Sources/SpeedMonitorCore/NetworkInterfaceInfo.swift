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

    public init(name: String, family: String, address: String?, isUp: Bool, isRunning: Bool, isLoopback: Bool) {
        self.name = name
        self.family = family
        self.address = address
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
    }
}
