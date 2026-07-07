import Foundation
import Hummingbird
import DrachmaCore
import DrachmaAuth
import DrachmaServer

// drachma-server — the RESTful API in front of the rates data, secured by the
// OAuth 2.1 authorization server. Runs a real HTTP microservice; the stdio
// drachma-mcp tool is unchanged and separate.

let resourceIdentifier = ProcessInfo.processInfo.environment["DRACHMA_RESOURCE"]
    ?? "http://127.0.0.1:8080"
let port = ProcessInfo.processInfo.environment["PORT"].flatMap(Int.init) ?? 8080

let oauth = OAuthServer(audience: resourceIdentifier)
// A demo public client (PKCE, no secret) — the agent case.
oauth.register(OAuthClient(
    id: "drachma-agent",
    redirectURIs: ["http://127.0.0.1/callback"],
    allowedScopes: ["rates:read"]
))

let router = DrachmaRouter.build(
    resourceIdentifier: resourceIdentifier,
    oauth: oauth,
    rates: CachedPairRatesClient(wrapping: CompositeRatesClient())
)

let app = Application(
    router: router,
    configuration: .init(address: .hostname("0.0.0.0", port: port))
)

try await app.runService()
