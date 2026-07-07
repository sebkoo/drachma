import Foundation

/// Where a rate came from — shown to the user, never hidden. The manifesto's
/// timestamp principle, extended to provenance.
public enum RateSource: String, Codable, Hashable, Sendable {
    /// Official ECB reference rates (via Frankfurter). ~30 currencies.
    case ecb
    /// Community-sourced daily rates (via currency-api). 200+ currencies,
    /// indicative — labeled as such wherever they appear.
    case community
}

/// One day's reference rates for a base currency.
public struct RatesSnapshot: Codable, Hashable, Sendable {
    /// ISO 4217 code the rates are quoted against, e.g. "EUR".
    public let base: String

    /// The ECB reference day the rates belong to, `yyyy-MM-dd`.
    /// The ECB publishes once per working day around 16:00 CET, so weekend
    /// queries carry Friday's date — surfaces should always show this date.
    public let date: String

    /// Quote-currency code → rate for 1 unit of `base`.
    /// `Decimal` keeps conversion arithmetic predictable; ECB reference rates
    /// carry at most 5–6 significant digits, well inside `Decimal` precision.
    public let rates: [String: Decimal]

    /// Which system the numbers came from; nil on older cached payloads.
    public let source: RateSource?

    public init(base: String, date: String, rates: [String: Decimal], source: RateSource? = nil) {
        self.base = base
        self.date = date
        self.rates = rates
        self.source = source
    }
}
