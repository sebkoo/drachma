import Foundation

/// Rates for a specific pair — the seam view models depend on once currency
/// coverage outgrows a single source.
public protocol PairRatesProviding: Sendable {
    func latestRates(base: String, quote: String) async throws -> RatesSnapshot
}

extension FrankfurterClient: PairRatesProviding {
    public func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        try await latestRates(base: base)
    }
}

/// One routing rule, honestly labeled: pairs the ECB covers get official
/// reference rates; everything else gets the community source, and the
/// snapshot's `source` tag rides to the UI either way.
public struct CompositeRatesClient: PairRatesProviding {
    private let ecb: any RatesClient
    private let community: any RatesClient
    private let ecbCodes: Set<String>

    public init(
        ecb: any RatesClient = FrankfurterClient(),
        community: any RatesClient = CommunityRatesClient(),
        ecbCodes: Set<String> = FrankfurterClient.supportedCurrencyCodes
    ) {
        self.ecb = ecb
        self.community = community
        self.ecbCodes = ecbCodes
    }

    public func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        if ecbCodes.contains(base.uppercased()), ecbCodes.contains(quote.uppercased()) {
            return try await ecb.latestRates(base: base)
        }
        return try await community.latestRates(base: base)
    }
}

/// Last-good fallback for pair lookups, reusing RatesCache. Cache entries are
/// keyed by base, so an offline fallback may carry either source's tag — the
/// label and date stay visible, which is the whole point.
public struct CachedPairRatesClient: PairRatesProviding {
    private let wrapped: any PairRatesProviding
    private let cache: RatesCache

    public init(wrapping wrapped: any PairRatesProviding, cache: RatesCache = RatesCache()) {
        self.wrapped = wrapped
        self.cache = cache
    }

    public func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        do {
            let fresh = try await wrapped.latestRates(base: base, quote: quote)
            await cache.store(fresh)
            return fresh
        } catch {
            if let lastGood = await cache.snapshot(base: base) {
                return lastGood
            }
            throw error
        }
    }
}
