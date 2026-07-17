import XCTest
import DrachmaAuthClient
@testable import DrachmaApp

/// Routes requests by path, so one transport can play token endpoint and
/// protected resource at once — no sockets, no server.
private final class RoutingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) -> (Data, Int)] = [:]
    private(set) var paths: [String] = []

    func on(_ path: String, _ handler: @escaping @Sendable (URLRequest) -> (Data, Int)) {
        handlers[path] = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        lock.withLock { paths.append(path) }
        guard let handler = handlers[path] else { return (Data(), 404) }
        return handler(request)
    }
}

private func tokenJSON(access: String, refresh: String) -> Data {
    Data("""
    {"access_token":"\(access)","token_type":"Bearer","expires_in":3600,
     "scope":"rates:read","refresh_token":"\(refresh)"}
    """.utf8)
}

private let rateJSON = Data("""
{"base":"USD","quote":"EUR","rate":0.876,"rateDate":"2026-07-06",
 "source":"ECB reference","disclaimer":"Reference rate, not a tradable quote."}
""".utf8)

@MainActor
final class ConnectViewModelTests: XCTestCase {
    // Lazy instead of a setUp() override: XCTestCase.setUp() is nonisolated
    // by declaration, and calling it from this @MainActor class's override
    // means sending non-Sendable self across that boundary — some toolchains
    // accept it, others don't. A fresh instance per test method makes a
    // lazily-cleared suite an equivalent, toolchain-independent stand-in.
    private lazy var defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "ConnectViewModelTests")!
        defaults.removePersistentDomain(forName: "ConnectViewModelTests")
        return defaults
    }()

    private func makeModel(
        transport: RoutingTransport,
        store: InMemoryTokenStore
    ) -> ConnectViewModel {
        let model = ConnectViewModel(
            transport: transport,
            makeStore: { _ in store },
            defaults: defaults
        )
        model.serverURLText = "http://127.0.0.1:8080"
        return model
    }

    private func storedTokens(secondsToExpiry: TimeInterval) -> OAuthTokens {
        OAuthTokens(
            accessToken: "stored-access",
            refreshToken: "stored-refresh",
            scope: "rates:read",
            expiresAt: Date().addingTimeInterval(secondsToExpiry)
        )
    }

    func testRestoreRehydratesFromTheStore() async {
        let store = InMemoryTokenStore(tokens: storedTokens(secondsToExpiry: 3600))
        let model = makeModel(transport: RoutingTransport(), store: store)

        await model.restore()

        guard case .connected(let grant) = model.phase else {
            return XCTFail("a stored grant should surface as connected")
        }
        XCTAssertEqual(grant.accessTokenSuffix, "access".suffix(6).description)
        XCTAssertTrue(grant.hasRefreshToken)
    }

    func testFetchRateSendsTheBearerAndShowsTheHonestLabel() async {
        let store = InMemoryTokenStore(tokens: storedTokens(secondsToExpiry: 3600))
        let transport = RoutingTransport()
        transport.on("/v1/rates") { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer stored-access"
            )
            return (rateJSON, 200)
        }
        let model = makeModel(transport: transport, store: store)

        await model.fetchRate()

        XCTAssertEqual(model.rateText, "1 USD = 0.876 EUR · ECB reference · 2026-07-06")
    }

    func testStaleTokenRefreshesBeforeTheProtectedCall() async {
        let store = InMemoryTokenStore(tokens: storedTokens(secondsToExpiry: 5))
        let transport = RoutingTransport()
        transport.on("/oauth/token") { _ in (tokenJSON(access: "fresh-access", refresh: "fresh-refresh"), 200) }
        transport.on("/v1/rates") { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer fresh-access",
                "the refreshed token rides the request, not the stale one"
            )
            return (rateJSON, 200)
        }
        let model = makeModel(transport: transport, store: store)

        await model.fetchRate()

        XCTAssertEqual(transport.paths.first, "/oauth/token", "refresh precedes the resource call")
        XCTAssertNotNil(model.rateText)
        XCTAssertEqual(try store.load()?.accessToken, "fresh-access")
    }

    func testDisconnectForgetsTheGrant() async {
        let store = InMemoryTokenStore(tokens: storedTokens(secondsToExpiry: 3600))
        let model = makeModel(transport: RoutingTransport(), store: store)
        await model.restore()

        await model.disconnect()

        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertNil(try store.load())
    }

    func testGarbageServerURLFailsBeforeAnyNetworking() async {
        let model = makeModel(transport: RoutingTransport(), store: InMemoryTokenStore())
        model.serverURLText = "not a url"

        await model.connect()

        guard case .failed = model.phase else {
            return XCTFail("a bad URL must fail fast, before the auth sheet")
        }
    }
}
