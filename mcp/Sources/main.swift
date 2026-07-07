import Foundation
import DrachmaCore
import MCP

// drachma-mcp — the AI-agent door to ECB reference rates. Speaks MCP over
// stdio; stdout belongs to the protocol, so never print to it.

let ratesClient = FrankfurterClient()

// MARK: - Tools

private let honestDataNote = """
Rates are ECB reference rates published once per working day around 16:00 CET \
— weekend queries return Friday's numbers, and the returned `date` field says \
which day the numbers belong to. Reference rates, not tradable quotes. \
Source: Frankfurter (keyless, ECB).
"""

let latestRatesTool = Tool(
    name: "latest_rates",
    description: "Latest ECB reference rates for a base currency. \(honestDataNote)",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "base": .object([
                "type": .string("string"),
                "description": .string("ISO 4217 base currency code, e.g. \"USD\". Defaults to \"EUR\"."),
            ]),
        ]),
    ])
)

let historicalRatesTool = Tool(
    name: "historical_rates",
    description: "ECB reference rates for a specific past working day (1999-01-04 onward). \(honestDataNote)",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "date": .object([
                "type": .string("string"),
                "description": .string("The reference day, formatted yyyy-MM-dd."),
            ]),
            "base": .object([
                "type": .string("string"),
                "description": .string("ISO 4217 base currency code. Defaults to \"EUR\"."),
            ]),
        ]),
        "required": .array([.string("date")]),
    ])
)

let convertTool = Tool(
    name: "convert",
    description: "Convert an amount between two currencies using ECB reference rates — latest by default, or a past day via `date`. \(honestDataNote)",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "amount": .object([
                "type": .string("number"),
                "description": .string("The amount to convert."),
            ]),
            "from": .object([
                "type": .string("string"),
                "description": .string("ISO 4217 source currency code."),
            ]),
            "to": .object([
                "type": .string("string"),
                "description": .string("ISO 4217 target currency code."),
            ]),
            "date": .object([
                "type": .string("string"),
                "description": .string("Optional reference day (yyyy-MM-dd); omit for the latest rates."),
            ]),
        ]),
        "required": .array([.string("amount"), .string("from"), .string("to")]),
    ])
)

// MARK: - Argument helpers

func stringArg(_ value: Value?) -> String? {
    if case let .string(string)? = value { return string }
    return nil
}

func decimalArg(_ value: Value?) -> Decimal? {
    switch value {
    case .int(let int)?: return Decimal(int)
    case .double(let double)?: return Decimal(double)
    case .string(let string)?: return Decimal(string: string)
    default: return nil
    }
}

func jsonText(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func textResult(_ text: String, isError: Bool = false) -> CallTool.Result {
    .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
}

struct ConversionAnswer: Encodable {
    let amount: Decimal
    let from: String
    let to: String
    let converted: Decimal
    let rateDate: String
    let source: String
}

// MARK: - Server

let server = Server(
    name: "drachma",
    version: DrachmaCore.version,
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [latestRatesTool, convertTool, historicalRatesTool])
}

await server.withMethodHandler(CallTool.self) { params in
    do {
        switch params.name {
        case latestRatesTool.name:
            let base = stringArg(params.arguments?["base"])?.uppercased() ?? "EUR"
            return textResult(try jsonText(try await ratesClient.latestRates(base: base)))

        case historicalRatesTool.name:
            guard let date = stringArg(params.arguments?["date"]) else {
                throw MCPError.invalidParams("historical_rates requires `date` (yyyy-MM-dd)")
            }
            let base = stringArg(params.arguments?["base"])?.uppercased() ?? "EUR"
            return textResult(try jsonText(try await ratesClient.rates(on: date, base: base)))

        case convertTool.name:
            guard let amount = decimalArg(params.arguments?["amount"]),
                  let from = stringArg(params.arguments?["from"])?.uppercased(),
                  let to = stringArg(params.arguments?["to"])?.uppercased()
            else {
                throw MCPError.invalidParams("convert requires `amount`, `from`, and `to`")
            }
            let snapshot: RatesSnapshot
            if let date = stringArg(params.arguments?["date"]) {
                snapshot = try await ratesClient.rates(on: date, base: from)
            } else {
                snapshot = try await ratesClient.latestRates(base: from)
            }
            let converted = try snapshot.convert(amount, from: from, to: to)
            let answer = ConversionAnswer(
                amount: amount,
                from: from,
                to: to,
                converted: converted,
                rateDate: snapshot.date,
                source: "ECB reference rates via Frankfurter"
            )
            return textResult(try jsonText(answer))

        default:
            throw MCPError.invalidParams("unknown tool: \(params.name)")
        }
    } catch let error as RatesClientError {
        return textResult("rates lookup failed: \(error)", isError: true)
    } catch let error as ConversionError {
        return textResult("conversion failed: \(error)", isError: true)
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
