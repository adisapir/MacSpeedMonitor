import Foundation

struct OUIVendorLookup: Sendable {
    static let shared = OUIVendorLookup.load()

    private let vendorsByHexPrefix: [String: String]
    private let prefixLengths: [Int]

    func vendorName(for bssid: String?) -> String {
        guard let hex = Self.normalizedHex(from: bssid), hex.count >= 6 else {
            return "Unknown"
        }

        if let vendor = vendorName(forNormalizedHex: hex) {
            return vendor
        }

        if Self.isLocallyAdministered(hex),
           let universalHex = Self.clearingLocalAdministrationBit(hex),
           let vendor = vendorName(forNormalizedHex: universalHex) {
            return "\(vendor) (derived BSSID)"
        }

        if Self.isLocallyAdministered(hex) {
            return "Private/Randomized MAC"
        }

        return "Unknown (\(Self.colonSeparatedPrefix(hex)))"
    }

    private func vendorName(forNormalizedHex hex: String) -> String? {
        for length in prefixLengths where hex.count >= length {
            let prefix = String(hex.prefix(length))
            if let vendor = vendorsByHexPrefix[prefix] {
                return vendor
            }
        }
        return nil
    }

    private static func load() -> OUIVendorLookup {
        guard let url = resourceURL,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return OUIVendorLookup(vendorsByHexPrefix: [:])
        }

        var vendorsByHexPrefix: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            guard let entry = vendorEntry(from: trimmed),
                  let prefix = normalizedPrefix(from: entry.prefix),
                  !entry.vendor.isEmpty
            else {
                continue
            }

            vendorsByHexPrefix[prefix] = entry.vendor
        }

        return OUIVendorLookup(vendorsByHexPrefix: vendorsByHexPrefix)
    }

    private init(vendorsByHexPrefix: [String: String]) {
        self.vendorsByHexPrefix = vendorsByHexPrefix
        self.prefixLengths = Array(Set(vendorsByHexPrefix.keys.map(\.count))).sorted(by: >)
    }

    private static var resourceURL: URL? {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: "oui-vendors", withExtension: "tsv")
        #else
        Bundle(for: BundleToken.self).url(forResource: "oui-vendors", withExtension: "tsv")
        #endif
    }

    private static func vendorEntry(from line: String) -> (prefix: String, vendor: String)? {
        if line.contains("\t") {
            let parts = line
                .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            guard parts.count == 2 else {
                return nil
            }
            return (parts[0], parts[1])
        }

        let parts = line
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count >= 2 else {
            return nil
        }

        if parts.count >= 3 {
            return (parts[0], parts.dropFirst(2).joined(separator: " "))
        }

        return (parts[0], parts[1])
    }

    private static func normalizedPrefix(from value: String) -> String? {
        let hex = value
            .uppercased()
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .filter { $0.isHexDigit } ?? ""

        guard hex.count >= 6, hex.count <= 12, hex.count.isMultiple(of: 2) else {
            return nil
        }

        return hex
    }

    private static func normalizedHex(from bssid: String?) -> String? {
        let hex = bssid?
            .uppercased()
            .filter { $0.isHexDigit } ?? ""

        guard hex.count >= 6 else {
            return nil
        }

        return hex
    }

    private static func isLocallyAdministered(_ hex: String) -> Bool {
        guard let firstOctet = firstOctet(from: hex) else {
            return false
        }

        return (firstOctet & 0x02) != 0
    }

    private static func clearingLocalAdministrationBit(_ hex: String) -> String? {
        guard let firstOctet = firstOctet(from: hex) else {
            return nil
        }

        let cleared = String(format: "%02X", firstOctet & 0xFD)
        return cleared + hex.dropFirst(2)
    }

    private static func firstOctet(from hex: String) -> UInt8? {
        guard hex.count >= 2 else {
            return nil
        }

        return UInt8(hex.prefix(2), radix: 16)
    }

    private static func colonSeparatedPrefix(_ hex: String) -> String {
        let prefix = String(hex.prefix(6))
        return stride(from: 0, to: prefix.count, by: 2)
            .map { index in
                let start = prefix.index(prefix.startIndex, offsetBy: index)
                let end = prefix.index(start, offsetBy: 2)
                return String(prefix[start..<end])
            }
            .joined(separator: ":")
    }
}

private final class BundleToken {}
