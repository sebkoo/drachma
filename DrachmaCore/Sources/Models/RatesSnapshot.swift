import Foundation

/// One day's ECB reference rates for a base currency, as served by Frankfurter.
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

    public init(base: String, date: String, rates: [String: Decimal]) {
        self.base = base
        self.date = date
        self.rates = rates
    }
}
