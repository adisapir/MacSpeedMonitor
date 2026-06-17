import XCTest
@testable import SpeedMonitorCore

final class OUIVendorLookupTests: XCTestCase {
    func testVendorLookupUsesWiresharkManufacturerPrefixes() {
        let lookup = OUIVendorLookup.shared

        XCTAssertEqual(
            lookup.vendorName(for: "b0:1f:47:12:c1:25"),
            "Heights Telecom T ltd"
        )
        XCTAssertEqual(
            lookup.vendorName(for: "b0:92:4a:ee:1b:75"),
            "Sagemcom Broadband SAS"
        )
        XCTAssertEqual(
            lookup.vendorName(for: "24:4B:FE:00:00:00"),
            "ASUSTek COMPUTER INC."
        )
    }
}
