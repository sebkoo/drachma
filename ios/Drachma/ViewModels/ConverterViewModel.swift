import Foundation
import Observation
import DrachmaCore

@Observable @MainActor
public final class ConverterViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public var amountText = "100"
    public var fromCurrency = "USD"
    public var toCurrency = "EUR"
    public private(set) var snapshot: RatesSnapshot?
    public private(set) var state: LoadState = .idle

    private let ratesClient: any RatesClient

    public init(ratesClient: any RatesClient) {
        self.ratesClient = ratesClient
    }

    public var amount: Decimal? {
        Decimal(string: amountText)
    }

    public var convertedAmount: Decimal? {
        guard let snapshot, let amount else { return nil }
        return try? snapshot.convert(amount, from: fromCurrency, to: toCurrency)
    }

    /// The honest timestamp — shown next to the number, always.
    public var rateDate: String? {
        snapshot?.date
    }

    public var availableCurrencies: [String] {
        guard let snapshot else { return [fromCurrency, toCurrency].sorted() }
        return Array(Set(snapshot.rates.keys).union([snapshot.base])).sorted()
    }

    public func load() async {
        state = .loading
        do {
            snapshot = try await ratesClient.latestRates(base: fromCurrency)
            state = .loaded
        } catch {
            state = .failed("Couldn't load rates. Check your connection and try again.")
        }
    }

    public func swapCurrencies() async {
        (fromCurrency, toCurrency) = (toCurrency, fromCurrency)
        await load()
    }
}
