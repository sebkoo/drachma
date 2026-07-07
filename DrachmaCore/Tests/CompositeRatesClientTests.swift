import XCTest
@testable import DrachmaCore

private struct FixedRates: RatesClient {
    let snapshot: RatesSnapshot
    var shouldFail = false

    func latestRates(base: String) async throws -> RatesSnapshot {
        if shouldFail { throw RatesClientError.badStatus(500) }
        return snapshot
    }

    func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await latestRates(base: base)
    }
}

final class CompositeRatesClientTests: XCTestCase {
    private let ecbSnapshot = RatesSnapshot(
        base: "USD", date: "2026-07-06",
        rates: ["EUR": Decimal(string: "0.876")!], source: .ecb
    )
    private let communitySnapshot = RatesSnapshot(
        base: "USD", date: "2026-07-07",
        rates: ["VND": 26150], source: .community
    )

    private var composite: CompositeRatesClient {
        CompositeRatesClient(
            ecb: FixedRates(snapshot: ecbSnapshot),
            community: FixedRates(snapshot: communitySnapshot),
            ecbCodes: ["USD", "EUR", "KRW"]
        )
    }

    func testEcbCoveredPairRoutesToEcb() async throws {
        let snapshot = try await composite.latestRates(base: "usd", quote: "eur")

        XCTAssertEqual(snapshot.source, .ecb)
    }

    func testNonEcbQuoteRoutesToCommunity() async throws {
        let snapshot = try await composite.latestRates(base: "USD", quote: "VND")

        XCTAssertEqual(snapshot.source, .community)
    }

    func testNonEcbBaseRoutesToCommunity() async throws {
        let snapshot = try await composite.latestRates(base: "VND", quote: "USD")

        XCTAssertEqual(snapshot.source, .community)
    }

    func testCachedPairFallsBackToLastGood() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = RatesCache(directory: directory)
        await cache.store(communitySnapshot)

        let failing = CompositeRatesClient(
            ecb: FixedRates(snapshot: ecbSnapshot, shouldFail: true),
            community: FixedRates(snapshot: communitySnapshot, shouldFail: true),
            ecbCodes: ["USD", "EUR"]
        )
        let client = CachedPairRatesClient(wrapping: failing, cache: cache)

        let lastGood = try await client.latestRates(base: "USD", quote: "EUR")

        XCTAssertEqual(lastGood, communitySnapshot, "the fallback keeps its source tag and date visible")
    }
}
