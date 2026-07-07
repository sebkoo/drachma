import XCTest
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import DrachmaAuth
@testable import DrachmaCore
@testable import DrachmaServer

private struct StubRates: PairRatesProviding {
    func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        RatesSnapshot(base: base, date: "2026-07-06", rates: [quote: Decimal(string: "0.876")!], source: .ecb)
    }
}

// Free helpers so @Sendable test closures never capture the XCTestCase.
private let resource = "http://127.0.0.1:8080"

private func makeApp(_ oauth: OAuthServer) -> some ApplicationProtocol {
    Application(router: DrachmaRouter.build(
        resourceIdentifier: resource, oauth: oauth, rates: StubRates()
    ))
}

private func makeOAuth() -> OAuthServer {
    let oauth = OAuthServer(audience: resource)
    oauth.register(OAuthClient(
        id: "agent", redirectURIs: ["http://127.0.0.1/callback"], allowedScopes: ["rates:read"]
    ))
    return oauth
}

private func jsonBody(_ dict: [String: Any]) throws -> ByteBuffer {
    ByteBuffer(data: try JSONSerialization.data(withJSONObject: dict))
}

private func decodeJSON(_ buffer: ByteBuffer?) -> [String: Any] {
    guard let buffer, let data = buffer.getData(at: 0, length: buffer.readableBytes),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}

final class DrachmaRouterTests: XCTestCase {

    func testHealthIsPublic() async throws {
        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(decodeJSON(response.body)["status"] as? String, "ok")
            }
        }
    }

    func testDiscoveryMetadataIsPublic() async throws {
        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(uri: "/.well-known/oauth-protected-resource", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(decodeJSON(response.body)["resource"] as? String, resource)
            }
        }
    }

    func testProtectedRatesRequire401WithoutToken() async throws {
        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(uri: "/v1/rates?base=USD&quote=EUR", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized)
                XCTAssertNotNil(response.headers[.wwwAuthenticate])
            }
        }
    }

    func testFullOAuthFlowThenRatesSucceeds() async throws {
        let oauth = makeOAuth()
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.challenge(for: verifier)!

        try await makeApp(oauth).test(.router) { client in
            // 1) authorize -> code
            let code: String = try await client.execute(
                uri: "/oauth/authorize", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBody([
                    "clientID": "agent", "redirectURI": "http://127.0.0.1/callback",
                    "codeChallenge": challenge, "codeChallengeMethod": "S256", "scope": ["rates:read"],
                ])
            ) { response in
                XCTAssertEqual(response.status, .ok)
                return decodeJSON(response.body)["code"] as! String
            }

            // 2) token -> access token
            let token: String = try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBody([
                    "grantType": "authorization_code", "code": code, "codeVerifier": verifier,
                    "clientID": "agent", "redirectURI": "http://127.0.0.1/callback",
                ])
            ) { response in
                XCTAssertEqual(response.status, .ok)
                return decodeJSON(response.body)["access_token"] as! String
            }

            // 3) protected resource with the bearer token
            try await client.execute(
                uri: "/v1/rates?base=USD&quote=EUR", method: .get,
                headers: [.authorization: "Bearer \(token)"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let json = decodeJSON(response.body)
                XCTAssertEqual(json["base"] as? String, "USD")
                XCTAssertEqual(json["quote"] as? String, "EUR")
                XCTAssertEqual(json["source"] as? String, "ECB reference")
            }
        }
    }

    func testWrongPKCEVerifierIsRejectedAtToken() async throws {
        let oauth = makeOAuth()
        let challenge = PKCE.challenge(for: "real-verifier")!

        try await makeApp(oauth).test(.router) { client in
            let code: String = try await client.execute(
                uri: "/oauth/authorize", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBody([
                    "clientID": "agent", "redirectURI": "http://127.0.0.1/callback",
                    "codeChallenge": challenge, "codeChallengeMethod": "S256", "scope": ["rates:read"],
                ])
            ) { response in decodeJSON(response.body)["code"] as! String }

            try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBody([
                    "grantType": "authorization_code", "code": code, "codeVerifier": "attacker",
                    "clientID": "agent", "redirectURI": "http://127.0.0.1/callback",
                ])
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
                XCTAssertEqual(decodeJSON(response.body)["error"] as? String, "invalid_grant")
            }
        }
    }
}
