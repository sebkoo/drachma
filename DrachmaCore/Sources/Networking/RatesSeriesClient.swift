/// Date-range rate series, kept as its own protocol rather than fattening
/// RatesClient — the history screen needs only this, and existing conformers
/// (stubs, the cache decorator) stay untouched.
public protocol RatesSeriesClient: Sendable {
    /// Reference rates from `from` to `to` (both `yyyy-MM-dd`) for one
    /// base/quote pair.
    func series(from: String, to: String, base: String, quote: String) async throws -> RatesSeries
}
