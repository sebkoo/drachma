import Foundation

/// A date range of ECB reference rates, as served by Frankfurter's
/// `start..end` endpoint. Days map to quote-currency rates; ECB publishes
/// working days only, so a 7-day window holds at most 5-6 points.
public struct RatesSeries: Codable, Hashable, Sendable {
    public let base: String
    public let startDate: String
    public let endDate: String
    /// day (yyyy-MM-dd) → quote code → rate for 1 unit of `base`.
    public let rates: [String: [String: Decimal]]

    enum CodingKeys: String, CodingKey {
        case base
        case startDate = "start_date"
        case endDate = "end_date"
        case rates
    }

    public init(base: String, startDate: String, endDate: String, rates: [String: [String: Decimal]]) {
        self.base = base
        self.startDate = startDate
        self.endDate = endDate
        self.rates = rates
    }

    /// The series for one quote currency, sorted by day.
    public func points(for quote: String) -> [(day: String, rate: Decimal)] {
        let code = quote.uppercased()
        return rates
            .compactMap { day, quotes in quotes[code].map { (day: day, rate: $0) } }
            .sorted { $0.day < $1.day }
    }
}
