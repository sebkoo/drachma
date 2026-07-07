import XCTest
import DrachmaCore
@testable import DrachmaApp

private struct StubSeries: RatesSeriesClient {
    var series: RatesSeries
    var shouldFail = false

    func series(from: String, to: String, base: String, quote: String) async throws -> RatesSeries {
        if shouldFail { throw RatesClientError.badStatus(503) }
        return series
    }
}

final class HistoryViewModelTests: XCTestCase {
    private let fixture = RatesSeries(
        base: "USD",
        startDate: "2026-06-30",
        endDate: "2026-07-06",
        rates: [
            "2026-07-01": ["EUR": Decimal(string: "0.8785")!],
            "2026-06-30": ["EUR": Decimal(string: "0.877")!],
        ]
    )

    func testWindowEndsAtNowAndSpansSevenDays() {
        let end = Date(timeIntervalSince1970: 1_783_468_800) // 2026-07-07 UTC

        let window = HistoryViewModel.window(endingAt: end, days: 7)

        XCTAssertEqual(window.from, "2026-06-30")
        XCTAssertEqual(window.to, "2026-07-07")
    }

    @MainActor
    func testLoadSortsPointsAndUppercasesCodes() async {
        let model = HistoryViewModel(seriesClient: StubSeries(series: fixture), base: "usd", quote: "eur")

        await model.load()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.points.map(\.day), ["2026-06-30", "2026-07-01"])
        XCTAssertEqual(model.base, "USD")
        XCTAssertEqual(model.quote, "EUR")
    }

    @MainActor
    func testFailureSetsFailedState() async {
        let model = HistoryViewModel(
            seriesClient: StubSeries(series: fixture, shouldFail: true),
            base: "USD",
            quote: "EUR"
        )

        await model.load()

        guard case .failed = model.state else {
            return XCTFail("expected failed state, got \(model.state)")
        }
        XCTAssertTrue(model.points.isEmpty)
    }
}
