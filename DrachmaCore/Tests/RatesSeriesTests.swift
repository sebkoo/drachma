import XCTest
@testable import DrachmaCore

final class RatesSeriesTests: XCTestCase {
    private let fixture = Data("""
    {"amount":1.0,"base":"USD","start_date":"2026-06-30","end_date":"2026-07-06",
     "rates":{"2026-07-01":{"EUR":0.8785},"2026-06-30":{"EUR":0.877},"2026-07-03":{"EUR":0.87604}}}
    """.utf8)

    func testSeriesBuildsRangeURLAndDecodes() async throws {
        let box = RequestBox()
        let client = FrankfurterClient(http: StubHTTP(data: fixture, statusCode: 200, box: box))

        let series = try await client.series(from: "2026-06-30", to: "2026-07-06", base: "USD", quote: "EUR")

        XCTAssertEqual(
            box.urls.first?.absoluteString,
            "https://api.frankfurter.dev/v1/2026-06-30..2026-07-06?base=USD&symbols=EUR"
        )
        XCTAssertEqual(series.base, "USD")
        XCTAssertEqual(series.startDate, "2026-06-30")
        XCTAssertEqual(series.rates.count, 3)
    }

    func testPointsAreSortedByDay() throws {
        let series = try JSONDecoder().decode(RatesSeries.self, from: fixture)

        let points = series.points(for: "eur")

        XCTAssertEqual(points.map(\.day), ["2026-06-30", "2026-07-01", "2026-07-03"])
        XCTAssertEqual((points[0].rate as NSDecimalNumber).doubleValue, 0.877, accuracy: 0.0001)
    }

    func testPointsForUnknownQuoteAreEmpty() throws {
        let series = try JSONDecoder().decode(RatesSeries.self, from: fixture)

        XCTAssertTrue(series.points(for: "XYZ").isEmpty)
    }
}
