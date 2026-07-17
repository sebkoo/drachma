import XCTest
@testable import DrachmaAuthClient

/// Records every request and replies with a canned (body, status).
final class CapturingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let reply: (Data, Int)

    init(body: Data, status: Int) {
        self.reply = (body, status)
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock { recorded.append(request) }
        return reply
    }
}

func tokenResponseJSON(
    access: String = "access-1",
    refresh: String? = "refresh-1",
    expiresIn: Int = 3600,
    scope: String = "rates:read"
) -> Data {
    var payload: [String: Any] = [
        "access_token": access,
        "token_type": "Bearer",
        "expires_in": expiresIn,
        "scope": scope,
    ]
    if let refresh { payload["refresh_token"] = refresh }
    return try! JSONSerialization.data(withJSONObject: payload)
}

private let configuration = OAuthClientConfiguration(
    baseURL: URL(string: "http://127.0.0.1:8080")!,
    clientID: "drachma-ios",
    redirectURI: "drachma://oauth/callback",
    scopes: ["rates:read"]
)

final class TokenClientTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_783_468_800)

    private func makeClient(_ transport: CapturingTransport) -> TokenClient {
        let epoch = self.epoch
        return TokenClient(configuration: configuration, transport: transport, now: { epoch })
    }

    private func sentBody(_ transport: CapturingTransport) throws -> [String: String] {
        let data = try XCTUnwrap(transport.requests.first?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    func testExchangeSpeaksTheServersWireFormat() async throws {
        let transport = CapturingTransport(body: tokenResponseJSON(), status: 200)
        _ = try await makeClient(transport).exchange(code: "the-code", codeVerifier: "the-verifier")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // camelCase in — the contract drachma-server's TokenRequest decodes.
        let body = try sentBody(transport)
        XCTAssertEqual(body["grantType"], "authorization_code")
        XCTAssertEqual(body["clientID"], "drachma-ios")
        XCTAssertEqual(body["redirectURI"], "drachma://oauth/callback")
        XCTAssertEqual(body["code"], "the-code")
        XCTAssertEqual(body["codeVerifier"], "the-verifier")
    }

    func testRefreshSendsTheRefreshGrant() async throws {
        let transport = CapturingTransport(body: tokenResponseJSON(), status: 200)
        _ = try await makeClient(transport).refresh(refreshToken: "old-refresh")

        let body = try sentBody(transport)
        XCTAssertEqual(body["grantType"], "refresh_token")
        XCTAssertEqual(body["refreshToken"], "old-refresh")
        XCTAssertEqual(body["clientID"], "drachma-ios")
        XCTAssertNil(body["code"], "refresh must not resend authorization-code fields")
    }

    func testSnakeCaseResponseBecomesAbsoluteExpiry() async throws {
        let transport = CapturingTransport(
            body: tokenResponseJSON(access: "a-2", refresh: "r-2", expiresIn: 120), status: 200
        )
        let tokens = try await makeClient(transport).exchange(code: "c", codeVerifier: "v")

        XCTAssertEqual(tokens.accessToken, "a-2")
        XCTAssertEqual(tokens.refreshToken, "r-2")
        XCTAssertEqual(tokens.scope, "rates:read")
        // expires_in is relative; the client pins it to receipt time.
        XCTAssertEqual(tokens.expiresAt, epoch.addingTimeInterval(120))
        XCTAssertTrue(tokens.isFresh(leeway: 30, now: epoch))
        XCTAssertFalse(tokens.isFresh(leeway: 30, now: epoch.addingTimeInterval(100)))
    }

    func testOAuthErrorCodeSurvivesTheErrorPath() async {
        let body = Data(#"{"error":"invalid_grant","error_description":"code reused"}"#.utf8)
        let transport = CapturingTransport(body: body, status: 400)

        do {
            _ = try await makeClient(transport).exchange(code: "stale", codeVerifier: "v")
            XCTFail("a 400 must throw")
        } catch let error as TokenClientError {
            XCTAssertEqual(error, .badResponse(status: 400, oauthError: "invalid_grant"))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testGarbageBodyIsMalformed() async {
        let transport = CapturingTransport(body: Data("not json".utf8), status: 200)
        do {
            _ = try await makeClient(transport).exchange(code: "c", codeVerifier: "v")
            XCTFail("garbage must throw")
        } catch let error as TokenClientError {
            XCTAssertEqual(error, .malformedBody)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
