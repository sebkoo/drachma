import Foundation

/// Decorates any RatesClient with last-good fallback: successes are cached,
/// failures fall back to the most recent cached snapshot. Stale is visible,
/// never silent — the snapshot's `date` rides along and every surface shows it.
public struct CachedRatesClient: RatesClient {
    private let wrapped: any RatesClient
    private let cache: RatesCache

    public init(wrapping wrapped: any RatesClient, cache: RatesCache = RatesCache()) {
        self.wrapped = wrapped
        self.cache = cache
    }

    public func latestRates(base: String) async throws -> RatesSnapshot {
        do {
            let fresh = try await wrapped.latestRates(base: base)
            await cache.store(fresh)
            return fresh
        } catch {
            if let lastGood = await cache.snapshot(base: base) {
                return lastGood
            }
            throw error
        }
    }

    public func rates(on day: String, base: String) async throws -> RatesSnapshot {
        // Historical days are immutable; no last-good semantics to add here.
        try await wrapped.rates(on: day, base: base)
    }
}
