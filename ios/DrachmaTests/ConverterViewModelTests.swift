import XCTest
import DrachmaCore
@testable import DrachmaApp

private struct StubRates: PairRatesProviding {
    var rates: [String: Decimal]
    var date = "2026-07-06"
    var source: RateSource? = .ecb
    var shouldFail = false

    func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        if shouldFail { throw RatesClientError.badStatus(500) }
        return RatesSnapshot(base: base, date: date, rates: rates, source: source)
    }
}

@MainActor
private func makeModel(_ stub: StubRates, catalog: [String] = []) -> ConverterViewModel {
    ConverterViewModel(ratesClient: stub, currencyCatalog: { catalog })
}

@MainActor
final class ConverterViewModelTests: XCTestCase {
    private let fixtureRates: [String: Decimal] = [
        "EUR": Decimal(string: "0.8")!,
        "KRW": 1400,
    ]

    func testLoadPopulatesSnapshotAndHonestDate() async {
        let model = makeModel(StubRates(rates: fixtureRates))

        await model.load()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.rateDate, "2026-07-06")
        XCTAssertEqual(model.snapshot?.base, "USD")
    }

    func testConvertedAmountUsesTheSnapshot() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()

        model.amountText = "100"
        model.toCurrency = "EUR"

        XCTAssertEqual(model.convertedAmount, Decimal(80))
    }

    func testInvalidAmountYieldsNoConversion() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()

        model.amountText = "not a number"

        XCTAssertNil(model.convertedAmount)
    }

    func testFailureSetsFailedStateAndConvertsNothing() async {
        let model = makeModel(StubRates(rates: [:], shouldFail: true))

        await model.load()

        guard case .failed = model.state else {
            return XCTFail("expected failed state, got \(model.state)")
        }
        XCTAssertNil(model.convertedAmount)
        XCTAssertNil(model.rateDate)
    }

    func testSwapExchangesCurrenciesAndReloads() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()

        await model.swapCurrencies()

        XCTAssertEqual(model.fromCurrency, "EUR")
        XCTAssertEqual(model.toCurrency, "USD")
        XCTAssertEqual(model.snapshot?.base, "EUR")
    }

    func testPastedValuesParse() {
        XCTAssertEqual(ConverterViewModel.parseAmount("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(ConverterViewModel.parseAmount("$100"), 100)
        XCTAssertEqual(ConverterViewModel.parseAmount("₩1,500"), 1500)
        XCTAssertEqual(ConverterViewModel.parseAmount(" 2 500 "), 2500)
        XCTAssertNil(ConverterViewModel.parseAmount("not a number"))
        XCTAssertNil(ConverterViewModel.parseAmount(""))
    }

    func testAvailableCurrenciesIncludeBaseAndQuotes() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()

        XCTAssertEqual(model.availableCurrencies, ["EUR", "KRW", "USD"])
    }

    func testCatalogUnionsWithECBCodesAndWinsOverSnapshot() async {
        let model = makeModel(StubRates(rates: fixtureRates), catalog: ["VND", "COP"])
        await model.load()

        XCTAssertTrue(model.availableCurrencies.contains("VND"))
        XCTAssertTrue(model.availableCurrencies.contains("KRW"), "ECB codes stay pickable")
    }

    func testSourceLabelsAreHonest() async {
        let ecb = makeModel(StubRates(rates: fixtureRates, source: .ecb))
        await ecb.load()
        XCTAssertEqual(ecb.sourceLabel, "ECB reference rate")

        let community = makeModel(StubRates(rates: ["VND": 26150], source: .community))
        await community.load()
        XCTAssertEqual(community.sourceLabel, "Community rate (currency-api) · indicative")
    }

    func testFilterMatchesCodePrefixAndNameSubstring() {
        let options = [
            CurrencyOption(code: "VND"),
            CurrencyOption(code: "KRW"),
            CurrencyOption(code: "USD"),
        ]

        XCTAssertEqual(ConverterViewModel.filter(options, query: "vnd").map(\.code), ["VND"])
        XCTAssertEqual(ConverterViewModel.filter(options, query: "").count, 3)
        // Name matching depends on the locale's currency names; "won" is a
        // safe substring of KRW's English name on CI (South Korean Won).
        XCTAssertTrue(ConverterViewModel.filter(options, query: "won").map(\.code).contains("KRW"))
    }

    func testUnknownCodeFallsBackToItself() {
        XCTAssertEqual(CurrencyOption(code: "zzz").code, "ZZZ")
        XCTAssertEqual(CurrencyOption(code: "zzz").name, "ZZZ")
    }

    func testRateCheckMeasuresAgainstMidMarket() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()
        model.toCurrency = "EUR" // mid: 0.8

        model.quotedRateText = "0.75"

        let check = try! XCTUnwrap(model.rateCheck)
        XCTAssertEqual((check.markupPercent as NSDecimalNumber).doubleValue, 6.25, accuracy: 0.001)
        XCTAssertEqual(check.verdict, "Very high — airport-kiosk territory")
        XCTAssertFalse(check.looksFlipped)
    }

    func testRateCheckFlagsBetterThanMidAndFlippedQuotes() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()
        model.toCurrency = "KRW" // mid: 1400

        model.quotedRateText = "0.0007" // KRW per USD entered upside down
        let flipped = try! XCTUnwrap(model.rateCheck)
        XCTAssertTrue(flipped.looksFlipped)

        model.quotedRateText = "1450" // better than mid
        let better = try! XCTUnwrap(model.rateCheck)
        XCTAssertTrue(better.markupPercent < 0)
        XCTAssertEqual(better.verdict, "Better than mid-market — double-check the quote")
    }

    func testRateCheckIsNilForEmptyOrInvalidInput() async {
        let model = makeModel(StubRates(rates: fixtureRates))
        await model.load()

        XCTAssertNil(model.rateCheck)
        model.quotedRateText = "abc"
        XCTAssertNil(model.rateCheck)
    }

    func testVerdictBands() {
        XCTAssertEqual(ConverterViewModel.verdict(forMarkupPercent: Decimal(string: "0.5")!), "Excellent — near mid-market")
        XCTAssertEqual(ConverterViewModel.verdict(forMarkupPercent: 2), "Fair — typical card or fintech spread")
        XCTAssertEqual(ConverterViewModel.verdict(forMarkupPercent: 4), "High — typical bank counter")
        XCTAssertEqual(ConverterViewModel.verdict(forMarkupPercent: 8), "Very high — airport-kiosk territory")
        XCTAssertEqual(ConverterViewModel.verdict(forMarkupPercent: 15), "Walk away")
    }

    func testHistoryHiddenForNonECBPairs() async {
        let model = makeModel(StubRates(rates: ["VND": 26150], source: .community))
        model.toCurrency = "VND"

        XCTAssertFalse(model.isHistoryAvailable)

        model.toCurrency = "EUR"
        XCTAssertTrue(model.isHistoryAvailable)
    }
}
