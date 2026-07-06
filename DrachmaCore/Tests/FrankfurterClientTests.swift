import XCTest
@testable import DrachmaCore

/// Records requests across concurrency boundaries for assertions.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL?) {
        lock.lock()
        defer { lock.unlock() }
        if let url { stored.append(url) }
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private struct StubHTTP: HTTPFetching {
    let data: Data
    let statusCode: Int
    let box: RequestBox

    func fetch(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        box.append(request.url)
        return (data, statusCode)
    }
}

final class FrankfurterClientTests: XCTestCase {
    private let fixture = Data("""
    {"amount":1.0,"base":"USD","date":"2026-07-03","rates":{"EUR":0.8523,"KRW":1381.2}}
    """.utf8)

    func testLatestRatesBuildsURLAndDecodes() async throws {
        let box = RequestBox()
        let client = FrankfurterClient(http: StubHTTP(data: fixture, statusCode: 200, box: box))

        let snapshot = try await client.latestRates(base: "USD")

        XCTAssertEqual(box.urls.first?.absoluteString, "https://api.frankfurter.dev/v1/latest?base=USD")
        XCTAssertEqual(snapshot.base, "USD")
        XCTAssertEqual(snapshot.date, "2026-07-03")
        XCTAssertEqual(snapshot.rates.count, 2)
        let krw = try XCTUnwrap(snapshot.rates["KRW"])
        XCTAssertEqual((krw as NSDecimalNumber).doubleValue, 1381.2, accuracy: 0.0001)
    }

    func testHistoricalRatesUsesDayPath() async throws {
        let box = RequestBox()
        let client = FrankfurterClient(http: StubHTTP(data: fixture, statusCode: 200, box: box))

        _ = try await client.rates(on: "2026-07-01", base: "EUR")

        XCTAssertEqual(box.urls.first?.absoluteString, "https://api.frankfurter.dev/v1/2026-07-01?base=EUR")
    }

    func testNon200Throws() async {
        let box = RequestBox()
        let client = FrankfurterClient(http: StubHTTP(data: Data(), statusCode: 503, box: box))

        do {
            _ = try await client.latestRates(base: "USD")
            XCTFail("expected badStatus")
        } catch let error as RatesClientError {
            XCTAssertEqual(error, .badStatus(503))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
