import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import DrachmaCore
import DrachmaAuth

/// Builds the drachma-server RESTful API: a public health check, OAuth 2.1
/// authorization-server + discovery endpoints, and an OAuth-protected rates
/// resource. Reuses DrachmaCore (rates) and DrachmaAuth (OAuth) — one core,
/// now a web service too.
public enum DrachmaRouter {
    public static func build(
        resourceIdentifier: String,
        oauth: OAuthServer,
        rates: any PairRatesProviding
    ) -> Router<BasicRequestContext> {
        let router = Router()

        // --- Public: liveness -------------------------------------------------
        router.get("/health") { _, _ in
            json(HealthResponse(), status: .ok)
        }

        // --- Public: RFC 9728 discovery --------------------------------------
        router.get("/.well-known/oauth-protected-resource") { _, _ in
            json(ProtectedResourceMetadata(
                resource: resourceIdentifier,
                authorizationServers: [resourceIdentifier],
                scopesSupported: ["rates:read"],
                bearerMethodsSupported: ["header"]
            ), status: .ok)
        }

        // --- OAuth: authorization endpoint (PKCE) ----------------------------
        router.post("/oauth/authorize") { request, context in
            let body = try await request.decode(as: AuthorizeRequest.self, context: context)
            do {
                let code = try oauth.authorize(
                    clientID: body.clientID,
                    redirectURI: body.redirectURI,
                    codeChallenge: body.codeChallenge,
                    codeChallengeMethod: body.codeChallengeMethod,
                    scope: Set(body.scope)
                )
                return json(AuthorizeResponse(code: code), status: .ok)
            } catch let error as OAuthError {
                return json(APIError(error: "invalid_request", errorDescription: "\(error)"),
                            status: .badRequest)
            }
        }

        // --- OAuth: token endpoint -------------------------------------------
        router.post("/oauth/token") { request, context in
            let body = try await request.decode(as: TokenRequest.self, context: context)
            guard body.grantType == "authorization_code" else {
                return json(APIError(error: "unsupported_grant_type", errorDescription: nil),
                            status: .badRequest)
            }
            do {
                let issued = try oauth.token(
                    code: body.code,
                    codeVerifier: body.codeVerifier,
                    clientID: body.clientID,
                    redirectURI: body.redirectURI
                )
                return json(TokenResponse(
                    accessToken: issued.access.value,
                    tokenType: "Bearer",
                    expiresIn: Int(issued.access.expiresAt.timeIntervalSinceNow),
                    scope: issued.access.scopes.sorted().joined(separator: " ")
                ), status: .ok)
            } catch {
                return json(APIError(error: "invalid_grant", errorDescription: "\(error)"),
                            status: .badRequest)
            }
        }

        // --- Protected resource: live rates (scope rates:read) ---------------
        router.get("/v1/rates") { request, _ in
            switch authorize(request, oauth: oauth, requiredScope: "rates:read") {
            case .failure(let response):
                return response
            case .success:
                break
            }

            let base = query(request, "base")?.uppercased() ?? "EUR"
            let quote = query(request, "quote")?.uppercased() ?? "USD"
            do {
                let snapshot = try await rates.latestRates(base: base, quote: quote)
                let value = try snapshot.convert(1, from: base, to: quote)
                return json(RateResponse(
                    base: base, quote: quote, rate: value, rateDate: snapshot.date,
                    source: snapshot.source == .community ? "community (currency-api), indicative" : "ECB reference"
                ), status: .ok)
            } catch {
                return json(APIError(error: "upstream_error", errorDescription: "Rate lookup failed"),
                            status: .badGateway)
            }
        }

        return router
    }

    // MARK: - Helpers

    enum AuthOutcome {
        case success
        case failure(Response)
    }

    /// Resource-server bearer check: 401 for missing/invalid tokens, 403 for
    /// insufficient scope. The auth logic lives in DrachmaAuth; this is the seam.
    static func authorize(_ request: Request, oauth: OAuthServer, requiredScope: String) -> AuthOutcome {
        guard let header = request.headers[.authorization], header.hasPrefix("Bearer ") else {
            return .failure(challenge(status: .unauthorized, error: "missing bearer token"))
        }
        let token = String(header.dropFirst("Bearer ".count))
        guard let access = oauth.introspect(token) else {
            return .failure(challenge(status: .unauthorized, error: "invalid or expired token"))
        }
        guard access.scopes.contains(requiredScope) else {
            return .failure(challenge(status: .forbidden, error: "insufficient_scope"))
        }
        return .success
    }

    static func challenge(status: HTTPResponse.Status, error: String) -> Response {
        var response = json(APIError(error: error, errorDescription: nil), status: status)
        response.headers[.wwwAuthenticate] = #"Bearer realm="drachma", scope="rates:read""#
        return response
    }

    static func query(_ request: Request, _ name: String) -> String? {
        request.uri.queryParameters[Substring(name)].map(String.init)
    }

    static func json<T: Encodable>(_ value: T, status: HTTPResponse.Status) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data(#"{"error":"encoding"}"#.utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(data: data)))
    }
}
