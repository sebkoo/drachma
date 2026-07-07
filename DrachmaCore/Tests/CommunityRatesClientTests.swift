import XCTest
@testable import DrachmaCore

final class CommunityRatesClientTests: XCTestCase {
    private let fixture = Data("""
    {"date":"2026-07-07","usd":{"eur":0.876,"vnd":26150.0,"cop":4102.5}}
    """.utf8)

    func testLatestBuildsURLDecodesAndTagsCommunity() async throws {
        let box = RequestBox()
        let client = CommunityRatesClient(
            http: StubHTTP(data: fixture, statusCode: 200, box: box),
            root: "https://example.test/currency-api"
        )

        let snapshot = try await client.latestRates(base: "USD")

        XCTAssertEqual(
            box.urls.first?.absoluteString,
            "https://example.test/currency-api@latest/v1/currencies/usd.json"
        )
        XCTAssertEqual(snapshot.base, "USD")
        XCTAssertEqual(snapshot.date, "2026-07-07")
        XCTAssertEqual(snapshot.source, .community)
        let vnd = try XCTUnwrap(snapshot.rates["VND"])
        XCTAssertEqual((vnd as NSDecimalNumber).doubleValue, 26150.0, accuracy: 0.01)
    }

    func testHistoricalUsesTheDateTag() async throws {
        let box = RequestBox()
        let client = CommunityRatesClient(
            http: StubHTTP(data: fixture, statusCode: 200, box: box),
            root: "https://example.test/currency-api"
        )

        _ = try await client.rates(on: "2026-07-01", base: "usd")

        XCTAssertEqual(
            box.urls.first?.absoluteString,
            "https://example.test/currency-api@2026-07-01/v1/currencies/usd.json"
        )
    }

    func testCurrencyCodesListsUppercasedSorted() async throws {
        let box = RequestBox()
        let names = Data(#"{"usd":"US Dollar","vnd":"Vietnamese Dong","cop":"Colombian Peso"}"#.utf8)
        let client = CommunityRatesClient(
            http: StubHTTP(data: names, statusCode: 200, box: box),
            root: "https://example.test/currency-api"
        )

        let codes = try await client.currencyCodes()

        XCTAssertEqual(codes, ["COP", "USD", "VND"])
        XCTAssertEqual(
            box.urls.first?.absoluteString,
            "https://example.test/currency-api@latest/v1/currencies.json"
        )
    }

    func testNon200Throws() async {
        let client = CommunityRatesClient(
            http: StubHTTP(data: Data(), statusCode: 404, box: RequestBox()),
            root: "https://example.test/currency-api"
        )

        do {
            _ = try await client.latestRates(base: "USD")
            XCTFail("expected badStatus")
        } catch let error as RatesClientError {
            XCTAssertEqual(error, .badStatus(404))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
