import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import NIOCore
import DrachmaAuth
import DrachmaAuthClient
@testable import DrachmaCore
@testable import DrachmaServer

// The loop-closing test: the *client* target's real types (Authorization
// Request/Callback, TokenClient) drive the *server's* real router in one
// process. If the two ends of the protocol drift, this fails in CI —
// not in a phone demo.

private let loopResource = "http://127.0.0.1:8080"

private struct LoopStubRates: PairRatesProviding {
    func latestRates(base: String, quote: String) async throws -> RatesSnapshot {
        RatesSnapshot(base: base, date: "2026-07-06", rates: [quote: Decimal(string: "0.876")!], source: .ecb)
    }
}

/// Adapts the client's `HTTPTransport` seam onto Hummingbird's in-process
/// test client, so `TokenClient` runs unmodified with no sockets.
private struct RouterTransport: HTTPTransport, @unchecked Sendable {
    let client: any TestClientProtocol

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let url = request.url,
              let method = HTTPRequest.Method(rawValue: request.httpMethod ?? "GET") else {
            throw CancellationError()
        }
        var headers = HTTPFields()
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            if let field = HTTPField.Name(name) { headers[field] = value }
        }
        let uri = url.path + (url.query.map { "?\($0)" } ?? "")
        return try await client.execute(
            uri: uri, method: method, headers: headers,
            body: request.httpBody.map { ByteBuffer(data: $0) }
        ) { response in
            (collate(response.body), Int(response.status.code))
        }
    }
}

private func collate(_ buffer: ByteBuffer?) -> Data {
    guard let buffer else { return Data() }
    return buffer.getData(at: 0, length: buffer.readableBytes) ?? Data()
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}

/// Re-encodes the authorize URL's own query items as the consent form's body
/// — exactly what the rendered HTML form does via hidden fields.
private func approvalForm(from url: URL, action: String) -> String {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    var pairs = items.map { ($0.name, $0.value ?? "") }
    pairs.append(("action", action))
    return pairs.map { "\($0.0.formEncoded)=\($0.1.formEncoded)" }.joined(separator: "&")
}

final class ClientServerLoopTests: XCTestCase {

    func testTheAppsExactFlowAgainstTheRealRouter() async throws {
        let oauth = OAuthServer(audience: loopResource)
        oauth.register(OAuthClient(
            id: "drachma-ios",
            redirectURIs: ["drachma://oauth/callback"],
            allowedScopes: ["rates:read"]
        ))
        let configuration = OAuthClientConfiguration(
            baseURL: URL(string: loopResource)!,
            clientID: "drachma-ios",
            redirectURI: "drachma://oauth/callback",
            scopes: ["rates:read"]
        )
        let request = try XCTUnwrap(AuthorizationRequest.make(configuration: configuration))

        let app = Application(router: DrachmaRouter.build(
            resourceIdentifier: loopResource, oauth: oauth, rates: LoopStubRates()
        ))
        try await app.test(.router) { client in
            // 1) Front channel: the exact URL the app opens renders consent.
            let authorizeURI = request.url.path + "?" + (request.url.query ?? "")
            try await client.execute(uri: authorizeURI, method: .get) { response in
                XCTAssertEqual(response.status, .ok)
            }

            // 2) The user taps Approve → 302 carrying code + state.
            let location: String = try await client.execute(
                uri: "/oauth/approve", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: approvalForm(from: request.url, action: "approve"))
            ) { response in
                XCTAssertEqual(response.status, .found)
                return response.headers[.location] ?? ""
            }

            // 3) The client parses the callback — state (CSRF) check included.
            let code = try AuthorizationCallback.code(
                from: XCTUnwrap(URL(string: location)), expecting: request.state
            )

            // 4) Back channel: the real TokenClient, PKCE verifier and all.
            let tokenClient = TokenClient(
                configuration: configuration,
                transport: RouterTransport(client: client)
            )
            let tokens = try await tokenClient.exchange(
                code: code, codeVerifier: request.codeVerifier
            )
            let refreshToken = try XCTUnwrap(tokens.refreshToken)

            // 5) The grant opens the protected resource…
            try await client.execute(
                uri: "/v1/rates?base=USD&quote=EUR", method: .get,
                headers: [.authorization: "Bearer \(tokens.accessToken)"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }

            // 6) …rotation works end to end…
            let rotated = try await tokenClient.refresh(refreshToken: refreshToken)
            XCTAssertNotEqual(rotated.accessToken, tokens.accessToken)
            try await client.execute(
                uri: "/v1/rates?base=USD&quote=EUR", method: .get,
                headers: [.authorization: "Bearer \(rotated.accessToken)"]
            ) { response in
                XCTAssertEqual(response.status, .ok)
            }

            // 7) …and replaying the dead refresh token is refused.
            do {
                _ = try await tokenClient.refresh(refreshToken: refreshToken)
                XCTFail("a rotated refresh token must not redeem twice")
            } catch let error as TokenClientError {
                XCTAssertEqual(error, .badResponse(status: 400, oauthError: "invalid_grant"))
            }
        }
    }
}
