import XCTest
@testable import DrachmaAuth

/// A movable clock the server can read across the @Sendable `now` boundary.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

final class OAuthServerTests: XCTestCase {
    private let audience = "https://drachma.local/mcp"
    private let redirect = "http://127.0.0.1/callback"
    private let clock = Clock(Date(timeIntervalSince1970: 1_783_468_800))

    private func makeServer() -> OAuthServer {
        let clock = self.clock
        let server = OAuthServer(audience: audience, now: { clock.now })
        server.register(OAuthClient(
            id: "drachma-agent",
            redirectURIs: [redirect],
            allowedScopes: ["rates:read"]
        ))
        return server
    }

    private func fullFlow(on server: OAuthServer) throws -> AccessToken {
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.challenge(for: verifier)!
        let code = try server.authorize(
            clientID: "drachma-agent",
            redirectURI: redirect,
            codeChallenge: challenge,
            codeChallengeMethod: PKCE.method,
            scope: ["rates:read"]
        )
        return try server.token(
            code: code, codeVerifier: verifier,
            clientID: "drachma-agent", redirectURI: redirect
        )
    }

    func testHappyPathIssuesAudienceBoundToken() throws {
        let token = try fullFlow(on: makeServer())
        XCTAssertEqual(token.audience, audience)
        XCTAssertEqual(token.scopes, ["rates:read"])
        XCTAssertFalse(token.value.isEmpty)
    }

    func testUnknownClientRejected() {
        let server = makeServer()
        XCTAssertThrowsError(try server.authorize(
            clientID: "ghost", redirectURI: redirect,
            codeChallenge: "x", codeChallengeMethod: PKCE.method, scope: []
        )) { XCTAssertEqual($0 as? OAuthError, .unknownClient) }
    }

    func testMismatchedRedirectRejected() {
        let server = makeServer()
        XCTAssertThrowsError(try server.authorize(
            clientID: "drachma-agent", redirectURI: "http://evil/callback",
            codeChallenge: "x", codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )) { XCTAssertEqual($0 as? OAuthError, .invalidRedirectURI) }
    }

    func testPlainMethodRejectedAtAuthorize() {
        let server = makeServer()
        XCTAssertThrowsError(try server.authorize(
            clientID: "drachma-agent", redirectURI: redirect,
            codeChallenge: "x", codeChallengeMethod: "plain", scope: ["rates:read"]
        )) { XCTAssertEqual($0 as? OAuthError, .unsupportedChallengeMethod) }
    }

    func testScopeBeyondClientGrantRejected() {
        let server = makeServer()
        XCTAssertThrowsError(try server.authorize(
            clientID: "drachma-agent", redirectURI: redirect,
            codeChallenge: "x", codeChallengeMethod: PKCE.method, scope: ["rates:write"]
        )) { XCTAssertEqual($0 as? OAuthError, .invalidScope) }
    }

    func testWrongVerifierFailsTokenExchange() throws {
        let server = makeServer()
        let challenge = PKCE.challenge(for: "the-real-verifier")!
        let code = try server.authorize(
            clientID: "drachma-agent", redirectURI: redirect,
            codeChallenge: challenge, codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )
        XCTAssertThrowsError(try server.token(
            code: code, codeVerifier: "attacker-guess",
            clientID: "drachma-agent", redirectURI: redirect
        )) { XCTAssertEqual($0 as? OAuthError, .pkceVerificationFailed) }
    }

    func testCodeIsSingleUse() throws {
        let server = makeServer()
        let verifier = PKCE.generateCodeVerifier()
        let code = try server.authorize(
            clientID: "drachma-agent", redirectURI: redirect,
            codeChallenge: PKCE.challenge(for: verifier)!,
            codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )
        _ = try server.token(code: code, codeVerifier: verifier, clientID: "drachma-agent", redirectURI: redirect)
        XCTAssertThrowsError(try server.token(
            code: code, codeVerifier: verifier, clientID: "drachma-agent", redirectURI: redirect
        )) { XCTAssertEqual($0 as? OAuthError, .invalidGrant) }
    }

    func testExpiredCodeRejected() throws {
        let server = makeServer()
        let verifier = PKCE.generateCodeVerifier()
        let code = try server.authorize(
            clientID: "drachma-agent", redirectURI: redirect,
            codeChallenge: PKCE.challenge(for: verifier)!,
            codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )
        clock.advance(120) // past the 60s code TTL
        XCTAssertThrowsError(try server.token(
            code: code, codeVerifier: verifier, clientID: "drachma-agent", redirectURI: redirect
        )) { XCTAssertEqual($0 as? OAuthError, .invalidGrant) }
    }

    func testIntrospectionHonorsExpiry() throws {
        let server = makeServer()
        let token = try fullFlow(on: server)

        XCTAssertEqual(server.introspect(token.value)?.value, token.value)
        XCTAssertNil(server.introspect("not-a-token"))

        clock.advance(4000) // past the 3600s token TTL
        XCTAssertNil(server.introspect(token.value))
    }
}
