import XCTest
@testable import DrachmaAuthClient

/// Counts refresh calls; optional delay keeps a refresh "in flight" long
/// enough for a second caller to arrive.
final class CountingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let reply: @Sendable (Int) -> (Data, Int)
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0, reply: @escaping @Sendable (Int) -> (Data, Int)) {
        self.delayNanoseconds = delayNanoseconds
        self.reply = reply
    }

    var count: Int {
        lock.withLock { callCount }
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let call = lock.withLock {
            callCount += 1
            return callCount
        }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return reply(call)
    }
}

final class FailingTransport: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        throw Offline()
    }
}

private let configuration = OAuthClientConfiguration(
    baseURL: URL(string: "http://127.0.0.1:8080")!,
    clientID: "drachma-ios",
    redirectURI: "drachma://oauth/callback",
    scopes: ["rates:read"]
)

final class OAuthSessionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_783_468_800)

    private func makeSession(
        stored: OAuthTokens?,
        transport: any HTTPTransport
    ) -> (OAuthSession, InMemoryTokenStore) {
        let epoch = self.epoch
        let store = InMemoryTokenStore(tokens: stored)
        let session = OAuthSession(
            store: store,
            tokenClient: TokenClient(configuration: configuration, transport: transport, now: { epoch }),
            leeway: 30,
            now: { epoch }
        )
        return (session, store)
    }

    private func tokens(
        access: String = "access-0",
        refresh: String? = "refresh-0",
        secondsToExpiry: TimeInterval
    ) -> OAuthTokens {
        OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            scope: "rates:read",
            expiresAt: epoch.addingTimeInterval(secondsToExpiry)
        )
    }

    func testFreshTokenNeverTouchesTheNetwork() async throws {
        let transport = CountingTransport { _ in (tokenResponseJSON(), 200) }
        let (session, _) = makeSession(stored: tokens(secondsToExpiry: 3600), transport: transport)

        let token = try await session.validAccessToken()

        XCTAssertEqual(token, "access-0")
        XCTAssertEqual(transport.count, 0)
    }

    func testStaleTokenIsRefreshedAndPersisted() async throws {
        let transport = CountingTransport { _ in
            (tokenResponseJSON(access: "access-1", refresh: "refresh-1"), 200)
        }
        // 10s to expiry < 30s leeway — stale by policy, not yet by the clock.
        let (session, store) = makeSession(stored: tokens(secondsToExpiry: 10), transport: transport)

        let token = try await session.validAccessToken()

        XCTAssertEqual(token, "access-1")
        XCTAssertEqual(transport.count, 1)
        XCTAssertEqual(try store.load()?.refreshToken, "refresh-1", "the rotated pair replaces the old one")
    }

    func testConcurrentCallersShareOneRefresh() async throws {
        // Refresh tokens are single-use: two racing refreshes would trip the
        // server's reuse detection. The actor must collapse them into one.
        let transport = CountingTransport(delayNanoseconds: 50_000_000) { call in
            (tokenResponseJSON(access: "access-\(call)", refresh: "refresh-\(call)"), 200)
        }
        let (session, _) = makeSession(stored: tokens(secondsToExpiry: 0), transport: transport)

        async let first = session.validAccessToken()
        async let second = session.validAccessToken()
        let (a, b) = try await (first, second)

        XCTAssertEqual(a, b)
        XCTAssertEqual(transport.count, 1, "single flight: exactly one wire refresh")
    }

    func testInvalidGrantSignsOutLocally() async throws {
        let transport = CountingTransport { _ in
            (Data(#"{"error":"invalid_grant"}"#.utf8), 400)
        }
        let (session, store) = makeSession(stored: tokens(secondsToExpiry: 0), transport: transport)

        do {
            _ = try await session.validAccessToken()
            XCTFail("refresh rejection must throw")
        } catch {}

        XCTAssertNil(try store.load(), "a dead grant should not haunt the Keychain")
    }

    func testNetworkFailureKeepsTheStoredGrant() async throws {
        // Offline ≠ signed out: a transport blip must not wipe tokens that
        // may still be perfectly refreshable when the network returns.
        let (session, store) = makeSession(stored: tokens(secondsToExpiry: 0), transport: FailingTransport())

        do {
            _ = try await session.validAccessToken()
            XCTFail("offline refresh must throw")
        } catch {}

        XCTAssertNotNil(try store.load())
    }

    func testNoRefreshTokenMeansNotConnected() async throws {
        let transport = CountingTransport { _ in (tokenResponseJSON(), 200) }
        let (session, store) = makeSession(
            stored: tokens(refresh: nil, secondsToExpiry: 0), transport: transport
        )

        do {
            _ = try await session.validAccessToken()
            XCTFail("an unrenewable grant must throw")
        } catch let error as OAuthSessionError {
            XCTAssertEqual(error, .notConnected)
        }
        XCTAssertEqual(transport.count, 0)
        XCTAssertNil(try store.load())
    }

    func testSignOutClearsTheStore() async throws {
        let transport = CountingTransport { _ in (tokenResponseJSON(), 200) }
        let (session, store) = makeSession(stored: tokens(secondsToExpiry: 3600), transport: transport)

        try await session.signOut()

        XCTAssertNil(try store.load())
    }
}
