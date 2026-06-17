import Foundation

struct OUIVendorLookup: Sendable {
    static let shared = OUIVendorLookup.load()

    private let vendorNames: [String]
    private let vendorIndexesByHexPrefix: [String: Int]
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
            if let vendorIndex = vendorIndexesByHexPrefix[prefix],
               vendorNames.indices.contains(vendorIndex) {
                return vendorNames[vendorIndex]
            }
        }
        return nil
    }

    private static func load() -> OUIVendorLookup {
        guard let url = resourceURL,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return OUIVendorLookup(vendorNames: [], vendorIndexesByHexPrefix: [:])
        }

        let parsedResource = parsedCompactedResource(from: contents)
        if !parsedResource.vendorNames.isEmpty, !parsedResource.vendorIndexesByHexPrefix.isEmpty {
            return OUIVendorLookup(
                vendorNames: parsedResource.vendorNames,
                vendorIndexesByHexPrefix: parsedResource.vendorIndexesByHexPrefix
            )
        }

        var legacyVendorNames: [String] = []
        var legacyVendorIndexesByName: [String: Int] = [:]
        var legacyVendorIndexesByHexPrefix: [String: Int] = [:]

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

            let vendorIndex = legacyVendorIndexesByName[entry.vendor] ?? {
                let index = legacyVendorNames.count
                legacyVendorIndexesByName[entry.vendor] = index
                legacyVendorNames.append(entry.vendor)
                return index
            }()

            legacyVendorIndexesByHexPrefix[prefix] = vendorIndex
        }

        return OUIVendorLookup(
            vendorNames: legacyVendorNames,
            vendorIndexesByHexPrefix: legacyVendorIndexesByHexPrefix
        )
    }

    private init(vendorNames: [String], vendorIndexesByHexPrefix: [String: Int]) {
        self.vendorNames = vendorNames
        self.vendorIndexesByHexPrefix = vendorIndexesByHexPrefix
        self.prefixLengths = Array(Set(vendorIndexesByHexPrefix.keys.map(\.count))).sorted(by: >)
    }

    private static var resourceURL: URL? {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: "oui-vendors", withExtension: "tsv")
        #else
        Bundle(for: BundleToken.self).url(forResource: "oui-vendors", withExtension: "tsv")
        #endif
    }

    private static func parsedCompactedResource(
        from contents: String
    ) -> (vendorNames: [String], vendorIndexesByHexPrefix: [String: Int]) {
        enum Section {
            case none
            case vendors
            case prefixes
        }

        var section = Section.none
        var vendorNames: [String] = []
        var vendorIndexesByHexPrefix: [String: Int] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            if trimmed == "@vendors" {
                section = .vendors
                continue
            }

            if trimmed == "@prefixes" {
                section = .prefixes
                continue
            }

            switch section {
            case .vendors:
                vendorNames.append(trimmed)

            case .prefixes:
                let parts = trimmed
                    .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

                guard parts.count == 2,
                      let prefix = normalizedPrefix(from: parts[0]),
                      let vendorIndex = Int(parts[1]),
                      vendorIndex >= 0
                else {
                    continue
                }

                vendorIndexesByHexPrefix[prefix] = vendorIndex

            case .none:
                continue
            }
        }

        return (vendorNames, vendorIndexesByHexPrefix)
    }

    private static func vendorEntry(from line: String) -> (prefix: String, vendor: String)? {
        if line.contains("\t") {
            let parts = line
                .split(separator: "\t", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            guard parts.count >= 2 else {
                return nil
            }

            return (parts[0], parts.count >= 3 ? parts[2] : parts[1])
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
        let components = value
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .map(String.init)
        let bits = components.count == 2 ? Int(components[1]) : nil
        let nibbleCount = bits.map { ($0 + 3) / 4 }
        let hex = components
            .first?
            .uppercased()
            .filter { $0.isHexDigit } ?? ""
        let prefixLength = nibbleCount ?? hex.count

        guard prefixLength >= 6, prefixLength <= 12, hex.count >= prefixLength else {
            return nil
        }

        return String(hex.prefix(prefixLength))
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
