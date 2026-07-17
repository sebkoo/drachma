import XCTest
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import DrachmaAuth
@testable import DrachmaCore
@testable import DrachmaServer

// The browser half of the native-app flow: GET renders consent, POST approve
// 302s the one-time code back to the app's custom scheme, and the token
// endpoint honors both grants.

private let frontResource = "http://127.0.0.1:8080"
private let appRedirect = "drachma://oauth/callback"

private struct StubPairRates: PairRatesProviding {
    func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        RatesSnapshot(base: base, date: "2026-07-06", rates: [quote: Decimal(string: "0.876")!], source: .ecb)
    }
}

private func makeApp(_ oauth: OAuthServer) -> some ApplicationProtocol {
    Application(router: DrachmaRouter.build(
        resourceIdentifier: frontResource, oauth: oauth, rates: StubPairRates()
    ))
}

private func makeOAuth() -> OAuthServer {
    let oauth = OAuthServer(audience: frontResource)
    oauth.register(OAuthClient(
        id: "drachma-ios", redirectURIs: [appRedirect], allowedScopes: ["rates:read"]
    ))
    return oauth
}

private func formEncode(_ pairs: [(String, String)]) -> String {
    pairs.map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
        return "\(k)=\(v)"
    }.joined(separator: "&")
}

private func authorizeParams(challenge: String, state: String = "st4te") -> [(String, String)] {
    [
        ("response_type", "code"),
        ("client_id", "drachma-ios"),
        ("redirect_uri", appRedirect),
        ("code_challenge", challenge),
        ("code_challenge_method", "S256"),
        ("scope", "rates:read"),
        ("state", state),
    ]
}

private func bodyString(_ buffer: ByteBuffer?) -> String {
    guard let buffer, let data = buffer.getData(at: 0, length: buffer.readableBytes) else { return "" }
    return String(decoding: data, as: UTF8.self)
}

private func decodeJSONBody(_ buffer: ByteBuffer?) -> [String: Any] {
    guard let buffer, let data = buffer.getData(at: 0, length: buffer.readableBytes),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

private func jsonBuffer(_ dict: [String: Any]) throws -> ByteBuffer {
    ByteBuffer(data: try JSONSerialization.data(withJSONObject: dict))
}

final class OAuthFrontChannelTests: XCTestCase {

    func testAuthorizePageRendersConsentForAKnownClient() async throws {
        let challenge = PKCE.challenge(for: PKCE.generateCodeVerifier())!
        let query = formEncode(authorizeParams(challenge: challenge))

        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(uri: "/oauth/authorize?\(query)", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let page = bodyString(response.body)
                XCTAssertTrue(page.contains("drachma-ios"), "the page names the asking client")
                XCTAssertTrue(page.contains("rates:read"), "the page lists the requested scope")
                XCTAssertTrue(page.contains("/oauth/approve"), "the form posts to the decision endpoint")
            }
        }
    }

    func testAuthorizePageRejectsUnknownRedirectWithoutRedirecting() async throws {
        let challenge = PKCE.challenge(for: PKCE.generateCodeVerifier())!
        var params = authorizeParams(challenge: challenge)
        params[2] = ("redirect_uri", "evil://phish")
        let query = formEncode(params)

        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(uri: "/oauth/authorize?\(query)", method: .get) { response in
                // Render, never redirect: a 302 here would be an open redirect.
                XCTAssertEqual(response.status, .badRequest)
                XCTAssertNil(response.headers[.location])
            }
        }
    }

    func testApproveRedirectsWithCodeAndStateThenExchangeWorks() async throws {
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.challenge(for: verifier)!
        var form = authorizeParams(challenge: challenge, state: "abc123")
        form.append(("action", "approve"))
        let body = formEncode(form)

        try await makeApp(makeOAuth()).test(.router) { client in
            let location: String = try await client.execute(
                uri: "/oauth/approve", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .found)
                return response.headers[.location] ?? ""
            }

            let callback = try XCTUnwrap(URLComponents(string: location))
            XCTAssertEqual(callback.scheme, "drachma")
            func value(_ name: String) -> String? {
                callback.queryItems?.first { $0.name == name }?.value
            }
            XCTAssertEqual(value("state"), "abc123", "state echoes back for the CSRF check")
            let code = try XCTUnwrap(value("code"))

            // The code from the browser leg redeems at the token endpoint.
            try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBuffer([
                    "grantType": "authorization_code", "code": code, "codeVerifier": verifier,
                    "clientID": "drachma-ios", "redirectURI": appRedirect,
                ])
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let json = decodeJSONBody(response.body)
                XCTAssertNotNil(json["access_token"])
                XCTAssertNotNil(json["refresh_token"], "the exchange hands out a rotating refresh token")
            }
        }
    }

    func testDenyRedirectsWithAccessDenied() async throws {
        let challenge = PKCE.challenge(for: PKCE.generateCodeVerifier())!
        var form = authorizeParams(challenge: challenge, state: "abc123")
        form.append(("action", "deny"))
        let body = formEncode(form)

        try await makeApp(makeOAuth()).test(.router) { client in
            try await client.execute(
                uri: "/oauth/approve", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .found)
                let location = response.headers[.location] ?? ""
                XCTAssertTrue(location.hasPrefix("drachma://oauth/callback"))
                XCTAssertTrue(location.contains("error=access_denied"))
                XCTAssertTrue(location.contains("state=abc123"))
                XCTAssertFalse(location.contains("code="), "no code on denial")
            }
        }
    }

    func testRefreshGrantRotatesAndReplayIsRejected() async throws {
        let oauth = makeOAuth()
        let verifier = PKCE.generateCodeVerifier()
        let code = try oauth.authorize(
            clientID: "drachma-ios", redirectURI: appRedirect,
            codeChallenge: PKCE.challenge(for: verifier)!,
            codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )

        try await makeApp(oauth).test(.router) { client in
            let firstRefresh: String = try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBuffer([
                    "grantType": "authorization_code", "code": code, "codeVerifier": verifier,
                    "clientID": "drachma-ios", "redirectURI": appRedirect,
                ])
            ) { response in
                XCTAssertEqual(response.status, .ok)
                return decodeJSONBody(response.body)["refresh_token"] as! String
            }

            // Rotate once…
            let secondRefresh: String = try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBuffer([
                    "grantType": "refresh_token", "refreshToken": firstRefresh,
                    "clientID": "drachma-ios",
                ])
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let json = decodeJSONBody(response.body)
                XCTAssertNotNil(json["access_token"])
                return json["refresh_token"] as! String
            }
            XCTAssertNotEqual(secondRefresh, firstRefresh)

            // …then replay the dead one: invalid_grant.
            try await client.execute(
                uri: "/oauth/token", method: .post,
                headers: [.contentType: "application/json"],
                body: try jsonBuffer([
                    "grantType": "refresh_token", "refreshToken": firstRefresh,
                    "clientID": "drachma-ios",
                ])
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
                XCTAssertEqual(decodeJSONBody(response.body)["error"] as? String, "invalid_grant")
            }
        }
    }
}
