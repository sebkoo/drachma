import XCTest
import DrachmaCore
@testable import DrachmaApp

private struct StubRates: RatesClient {
    var rates: [String: Decimal]
    var date = "2026-07-06"
    var shouldFail = false

    func latestRates(base: String) async throws -> RatesSnapshot {
        if shouldFail { throw RatesClientError.badStatus(500) }
        return RatesSnapshot(base: base, date: date, rates: rates)
    }

    func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await latestRates(base: base)
    }
}

@MainActor
final class ConverterViewModelTests: XCTestCase {
    private let fixtureRates: [String: Decimal] = [
        "EUR": Decimal(string: "0.8")!,
        "KRW": 1400,
    ]

    func testLoadPopulatesSnapshotAndHonestDate() async {
        let model = ConverterViewModel(ratesClient: StubRates(rates: fixtureRates))

        await model.load()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.rateDate, "2026-07-06")
        XCTAssertEqual(model.snapshot?.base, "USD")
    }

    func testConvertedAmountUsesTheSnapshot() async {
        let model = ConverterViewModel(ratesClient: StubRates(rates: fixtureRates))
        await model.load()

        model.amountText = "100"
        model.toCurrency = "EUR"

        XCTAssertEqual(model.convertedAmount, Decimal(80))
    }

    func testInvalidAmountYieldsNoConversion() async {
        let model = ConverterViewModel(ratesClient: StubRates(rates: fixtureRates))
        await model.load()

        model.amountText = "not a number"

        XCTAssertNil(model.convertedAmount)
    }

    func testFailureSetsFailedStateAndConvertsNothing() async {
        let model = ConverterViewModel(ratesClient: StubRates(rates: [:], shouldFail: true))

        await model.load()

        guard case .failed = model.state else {
            return XCTFail("expected failed state, got \(model.state)")
        }
        XCTAssertNil(model.convertedAmount)
        XCTAssertNil(model.rateDate)
    }

    func testSwapExchangesCurrenciesAndReloads() async {
        let model = ConverterViewModel(ratesClient: StubRates(rates: fixtureRates))
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
        let model = ConverterViewModel(ratesClient: StubRates(rates: fixtureRates))
        await model.load()

        XCTAssertEqual(model.availableCurrencies, ["EUR", "KRW", "USD"])
    }
}
