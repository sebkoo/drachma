import XCTest
@testable import DrachmaCore

final class DrachmaCoreTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(DrachmaCore.version, "0.0.1")
    }
}
