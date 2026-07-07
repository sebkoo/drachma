import Foundation
import Observation
import DrachmaCore

public struct RatePoint: Identifiable, Hashable, Sendable {
    public let day: String
    public let rate: Decimal

    public var id: String { day }

    public var rateAsDouble: Double {
        (rate as NSDecimalNumber).doubleValue
    }
}

@Observable @MainActor
public final class HistoryViewModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public let base: String
    public let quote: String
    public private(set) var points: [RatePoint] = []
    public private(set) var state: LoadState = .loading

    private let seriesClient: any RatesSeriesClient
    private let now: @Sendable () -> Date

    public init(
        seriesClient: any RatesSeriesClient,
        base: String,
        quote: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.seriesClient = seriesClient
        self.base = base.uppercased()
        self.quote = quote.uppercased()
        self.now = now
    }

    public func load() async {
        state = .loading
        let (from, to) = Self.window(endingAt: now(), days: 7)
        do {
            let series = try await seriesClient.series(from: from, to: to, base: base, quote: quote)
            points = series.points(for: quote).map { RatePoint(day: $0.day, rate: $0.rate) }
            state = .loaded
        } catch {
            state = .failed("Couldn't load the history. Check your connection and try again.")
        }
    }

    /// The last `days` days ending at `endingAt`, as yyyy-MM-dd (UTC).
    /// Pure date math — nonisolated on purpose.
    nonisolated static func window(endingAt end: Date, days: Int) -> (from: String, to: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }
}
