import Foundation
import DrachmaCore
import MCP

// drachma-mcp — the AI-agent door to ECB reference rates. Speaks MCP over
// stdio; stdout belongs to the protocol, so never print to it.

let ratesClient = FrankfurterClient()

let latestRatesTool = Tool(
    name: "latest_rates",
    description: """
    Latest ECB reference rates for a base currency. Rates are published once \
    per ECB working day around 16:00 CET, so weekend queries return Friday's \
    rates — the returned `date` field says which day the numbers belong to. \
    Reference rates, not tradable quotes. Source: Frankfurter (keyless, ECB).
    """,
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

let server = Server(
    name: "drachma",
    version: DrachmaCore.version,
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [latestRatesTool])
}

await server.withMethodHandler(CallTool.self) { params in
    guard params.name == latestRatesTool.name else {
        throw MCPError.invalidParams("unknown tool: \(params.name)")
    }

    var base = "EUR"
    if case let .string(requested)? = params.arguments?["base"] {
        base = requested.uppercased()
    }

    do {
        let snapshot = try await ratesClient.latestRates(base: base)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
    } catch let error as RatesClientError {
        return .init(
            content: [.text(text: "rates lookup failed: \(error)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
