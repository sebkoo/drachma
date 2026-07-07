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
    /// The full pickable catalog (community list ∪ ECB); falls back to the
    /// snapshot's codes until it loads, and stays optional — a catalog failure
    /// must never block converting.
    public private(set) var catalog: [String] = []

    private let ratesClient: any PairRatesProviding
    private let currencyCatalog: @Sendable () async throws -> [String]

    public init(
        ratesClient: any PairRatesProviding,
        currencyCatalog: @escaping @Sendable () async throws -> [String] = {
            try await CommunityRatesClient().currencyCodes()
        }
    ) {
        self.ratesClient = ratesClient
        self.currencyCatalog = currencyCatalog
    }

    public var amount: Decimal? {
        Self.parseAmount(amountText)
    }

    /// Tolerant of pasted values — currency symbols, grouping commas, spaces:
    /// "1,234.56", "$100", "₩1,500" all parse. (A recurring complaint in
    /// competitor reviews is amount fields that reject pasted text.)
    /// Locale-aware separators ("1.234,56") arrive with localization.
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text.filter { $0.isNumber || $0 == "." }
        guard cleaned.contains(where: \.isNumber) else { return nil }
        return Decimal(string: cleaned)
    }

    public var convertedAmount: Decimal? {
        guard let snapshot, let amount else { return nil }
        return try? snapshot.convert(amount, from: fromCurrency, to: toCurrency)
    }

    /// The honest timestamp — shown next to the number, always.
    public var rateDate: String? {
        snapshot?.date
    }

    /// The honest provenance — which system the number came from.
    public var sourceLabel: String? {
        switch snapshot?.source {
        case .ecb: "ECB reference rate"
        case .community: "Community rate (currency-api) · indicative"
        case nil: nil
        }
    }

    /// History charts ride the ECB series endpoint, so they exist only for
    /// pairs the ECB covers — hidden honestly otherwise.
    public var isHistoryAvailable: Bool {
        FrankfurterClient.supportedCurrencyCodes.contains(fromCurrency.uppercased())
            && FrankfurterClient.supportedCurrencyCodes.contains(toCurrency.uppercased())
    }

    public var availableCurrencies: [String] {
        if !catalog.isEmpty { return catalog }
        guard let snapshot else { return [fromCurrency, toCurrency].sorted() }
        return Array(Set(snapshot.rates.keys).union([snapshot.base])).sorted()
    }

    public func load() async {
        state = .loading
        if catalog.isEmpty, let codes = try? await currencyCatalog(), !codes.isEmpty {
            catalog = Set(codes).union(FrankfurterClient.supportedCurrencyCodes).sorted()
        }
        do {
            snapshot = try await ratesClient.latestRates(base: fromCurrency, quote: toCurrency)
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
