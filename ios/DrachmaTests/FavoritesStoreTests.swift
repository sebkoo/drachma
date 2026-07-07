import XCTest
@testable import DrachmaApp

private struct TwoPairTier: EntitlementProviding {
    let maxFavoritePairs = 2
}

final class FavoritesStoreTests: XCTestCase {
    // XCTest lifecycle overrides are nonisolated, so the class must not be
    // @MainActor under strict concurrency — each test method is, instead.
    // (Caught by CI's stricter toolchain; the local one let it slide.)
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FavoritesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testAddPersistsAcrossStoreInstances() {
        let first = FavoritesStore(defaults: defaults)
        XCTAssertTrue(first.add(FavoritePair(base: "usd", quote: "krw")))

        let reloaded = FavoritesStore(defaults: defaults)

        XCTAssertEqual(reloaded.pairs, [FavoritePair(base: "USD", quote: "KRW")])
    }

    @MainActor
    func testDuplicateAddIsRejected() {
        let store = FavoritesStore(defaults: defaults)
        store.add(FavoritePair(base: "USD", quote: "EUR"))

        XCTAssertFalse(store.add(FavoritePair(base: "usd", quote: "eur")))
        XCTAssertEqual(store.pairs.count, 1)
    }

    @MainActor
    func testFreeTierCapsAtFivePairs() {
        let store = FavoritesStore(defaults: defaults)
        let quotes = ["EUR", "KRW", "JPY", "GBP", "CHF"]
        for quote in quotes {
            XCTAssertTrue(store.add(FavoritePair(base: "USD", quote: quote)))
        }

        XCTAssertTrue(store.isAtLimit)
        XCTAssertFalse(store.add(FavoritePair(base: "USD", quote: "CAD")))
        XCTAssertEqual(store.pairs.count, 5)
    }

    @MainActor
    func testTheSeamIsRealNotHardcoded() {
        let store = FavoritesStore(entitlements: TwoPairTier(), defaults: defaults)
        store.add(FavoritePair(base: "USD", quote: "EUR"))
        store.add(FavoritePair(base: "USD", quote: "KRW"))

        XCTAssertTrue(store.isAtLimit)
        XCTAssertFalse(store.add(FavoritePair(base: "USD", quote: "JPY")))
    }

    @MainActor
    func testRemoveFreesASlot() {
        let store = FavoritesStore(entitlements: TwoPairTier(), defaults: defaults)
        let pair = FavoritePair(base: "USD", quote: "EUR")
        store.add(pair)
        store.add(FavoritePair(base: "USD", quote: "KRW"))

        store.remove(pair)

        XCTAssertFalse(store.isAtLimit)
        XCTAssertTrue(store.add(FavoritePair(base: "USD", quote: "JPY")))
    }
}
