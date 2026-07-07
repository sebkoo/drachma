import XCTest
@testable import DrachmaCore

final class ConversionTests: XCTestCase {
    // 1 USD = 0.8 EUR = 1400 KRW
    private let snapshot = RatesSnapshot(
        base: "USD",
        date: "2026-07-06",
        rates: ["EUR": Decimal(string: "0.8")!, "KRW": Decimal(string: "1400")!]
    )

    private func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    func testBaseToQuote() throws {
        XCTAssertEqual(double(try snapshot.convert(100, from: "USD", to: "KRW")), 140_000, accuracy: 0.001)
    }

    func testQuoteToBase() throws {
        XCTAssertEqual(double(try snapshot.convert(140, from: "KRW", to: "USD")), 0.1, accuracy: 0.001)
    }

    func testCrossRate() throws {
        // 100 EUR -> USD -> KRW: 100 * 1400 / 0.8 = 175,000
        XCTAssertEqual(double(try snapshot.convert(100, from: "EUR", to: "KRW")), 175_000, accuracy: 0.001)
    }

    func testSameCurrencyIsIdentity() throws {
        XCTAssertEqual(try snapshot.convert(42, from: "eur", to: "EUR"), 42)
    }

    func testLowercaseCodesAreAccepted() throws {
        XCTAssertEqual(double(try snapshot.convert(1, from: "usd", to: "krw")), 1400, accuracy: 0.001)
    }

    func testUnknownCurrencyThrows() {
        XCTAssertThrowsError(try snapshot.convert(1, from: "USD", to: "XYZ")) { error in
            XCTAssertEqual(error as? ConversionError, .unknownCurrency("XYZ"))
        }
    }
}
