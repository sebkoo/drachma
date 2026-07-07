import XCTest
@testable import DrachmaCore

private struct AlwaysFails: RatesClient {
    func latestRates(base: String) async throws -> RatesSnapshot {
        throw RatesClientError.badStatus(503)
    }
    func rates(on day: String, base: String) async throws -> RatesSnapshot {
        throw RatesClientError.badStatus(503)
    }
}

private struct AlwaysSucceeds: RatesClient {
    let snapshot: RatesSnapshot
    func latestRates(base: String) async throws -> RatesSnapshot { snapshot }
    func rates(on day: String, base: String) async throws -> RatesSnapshot { snapshot }
}

final class RatesCacheTests: XCTestCase {
    private let fixture = RatesSnapshot(
        base: "USD",
        date: "2026-07-06",
        rates: ["EUR": Decimal(string: "0.87604")!]
    )

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testStoreAndLookupRoundTrip() async {
        let cache = RatesCache(directory: temporaryDirectory())

        await cache.store(fixture)
        let hit = await cache.snapshot(base: "usd")

        XCTAssertEqual(hit, fixture)
    }

    func testSurvivesANewCacheInstanceViaDisk() async {
        let directory = temporaryDirectory()

        await RatesCache(directory: directory).store(fixture)
        let reloaded = await RatesCache(directory: directory).snapshot(base: "USD")

        XCTAssertEqual(reloaded, fixture)
    }

    func testMissReturnsNil() async {
        let cache = RatesCache(directory: temporaryDirectory())

        let miss = await cache.snapshot(base: "USD")

        XCTAssertNil(miss)
    }

    func testSuccessIsStoredForLater() async throws {
        let directory = temporaryDirectory()
        let client = CachedRatesClient(
            wrapping: AlwaysSucceeds(snapshot: fixture),
            cache: RatesCache(directory: directory)
        )

        _ = try await client.latestRates(base: "USD")

        let stored = await RatesCache(directory: directory).snapshot(base: "USD")
        XCTAssertEqual(stored, fixture)
    }

    func testFailureFallsBackToLastGood() async throws {
        let directory = temporaryDirectory()
        let cache = RatesCache(directory: directory)
        await cache.store(fixture)

        let client = CachedRatesClient(wrapping: AlwaysFails(), cache: cache)
        let lastGood = try await client.latestRates(base: "USD")

        XCTAssertEqual(lastGood, fixture)
        XCTAssertEqual(lastGood.date, "2026-07-06", "the stale date must ride along — stale is visible, never silent")
    }

    func testFailureWithEmptyCacheRethrows() async {
        let client = CachedRatesClient(
            wrapping: AlwaysFails(),
            cache: RatesCache(directory: temporaryDirectory())
        )

        do {
            _ = try await client.latestRates(base: "USD")
            XCTFail("expected the underlying error")
        } catch let error as RatesClientError {
            XCTAssertEqual(error, .badStatus(503))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
