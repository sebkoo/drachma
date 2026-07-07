import Foundation
import Observation
import DrachmaCore

/// A pickable currency: ISO code plus a display name resolved through
/// Foundation's Locale — offline, and localized to the user's language
/// ("Vietnamese Dong" / "베트남 동"), so search-by-country works for free.
public struct CurrencyOption: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String) {
        let upper = code.uppercased()
        self.code = upper
        let localized = Locale.current.localizedString(forCurrencyCode: upper)
        self.name = (localized == nil || localized == upper) ? upper : localized!
    }
}

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
    /// Rate check: the rate a counter/kiosk offered, in the displayed
    /// direction (1 from-currency = ? to-currency).
    public var quotedRateText = ""
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

    public var currencyOptions: [CurrencyOption] {
        availableCurrencies.map(CurrencyOption.init(code:))
    }

    /// Matches the code by prefix and the (localized) name by substring, so
    /// "vnd", "viet", and "won" all find their currency. Pure — testable
    /// without a locale fixture.
    nonisolated static func filter(_ options: [CurrencyOption], query: String) -> [CurrencyOption] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.code.lowercased().hasPrefix(trimmed) || $0.name.lowercased().contains(trimmed)
        }
    }

    public struct RateCheckResult: Equatable, Sendable {
        /// Positive = the quote is worse than mid-market by this percent.
        public let markupPercent: Decimal
        public let verdict: String
        /// The quote is wildly off mid-market — probably entered in the
        /// opposite direction (KRW per USD instead of USD per KRW).
        public let looksFlipped: Bool
    }

    /// The anti-rip-off meter: no external data — today's mid-market rate is
    /// the yardstick every counter quote gets measured against.
    public var rateCheck: RateCheckResult? {
        guard let snapshot,
              let quoted = Self.parseAmount(quotedRateText), quoted > 0,
              let mid = try? snapshot.convert(1, from: fromCurrency, to: toCurrency), mid > 0
        else { return nil }

        let markup = (mid - quoted) / mid * 100
        let ratio = quoted / mid
        return RateCheckResult(
            markupPercent: markup,
            verdict: Self.verdict(forMarkupPercent: markup),
            looksFlipped: ratio < Decimal(string: "0.05")! || ratio > 20
        )
    }

    /// Bands follow the spreads travelers actually meet: fintech cards run
    /// ~0.5–1%, bank counters ~2–5%, airport kiosks ~5–12%.
    nonisolated static func verdict(forMarkupPercent markup: Decimal) -> String {
        switch markup {
        case ..<0: "Better than mid-market — double-check the quote"
        case ..<1: "Excellent — near mid-market"
        case ..<3: "Fair — typical card or fintech spread"
        case ..<6: "High — typical bank counter"
        case ..<12: "Very high — airport-kiosk territory"
        default: "Walk away"
        }
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
