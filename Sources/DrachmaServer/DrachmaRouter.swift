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

        // --- OAuth: hosted authorize page (front channel, RFC 6749 §4.1.1) ---
        // The browser half of the native-app flow: ASWebAuthenticationSession
        // lands here, the user approves, and the one-time code rides the 302
        // back to the app's custom-scheme redirect. Validation failures
        // *render* — redirecting to an unvalidated URI is an open redirect.
        router.get("/oauth/authorize") { request, _ in
            let query = queryValues(request)
            guard let params = AuthorizePageParams({ query[$0] }) else {
                return html(errorPage("Missing authorization parameters."), status: .badRequest)
            }
            guard params.responseType == "code" else {
                return html(errorPage("Only response_type=code is supported."), status: .badRequest)
            }
            guard oauth.isRegistered(clientID: params.clientID, redirectURI: params.redirectURI) else {
                return html(errorPage("Unknown client or redirect URI."), status: .badRequest)
            }
            guard params.codeChallengeMethod == PKCE.method else {
                return html(errorPage("PKCE with S256 is required."), status: .badRequest)
            }
            return html(consentPage(params), status: .ok)
        }

        // --- OAuth: consent decision (front channel, form POST) --------------
        // Client + redirect were validated at render time and are re-checked
        // here; from this point errors may redirect (§4.1.2.1), because the
        // destination is proven to belong to the client.
        router.post("/oauth/approve") { request, _ in
            let form = try await formValues(request)
            guard let params = AuthorizePageParams({ form[$0] }) else {
                return html(errorPage("Missing authorization parameters."), status: .badRequest)
            }
            guard oauth.isRegistered(clientID: params.clientID, redirectURI: params.redirectURI) else {
                return html(errorPage("Unknown client or redirect URI."), status: .badRequest)
            }
            guard form["action"] == "approve" else {
                return redirect(params.redirectURI, query: [
                    ("error", "access_denied"), ("state", params.state),
                ])
            }
            do {
                let code = try oauth.authorize(
                    clientID: params.clientID,
                    redirectURI: params.redirectURI,
                    codeChallenge: params.codeChallenge,
                    codeChallengeMethod: params.codeChallengeMethod,
                    scope: params.scopes
                )
                return redirect(params.redirectURI, query: [
                    ("code", code), ("state", params.state),
                ])
            } catch let error as OAuthError {
                return redirect(params.redirectURI, query: [
                    ("error", "invalid_request"), ("error_description", "\(error)"), ("state", params.state),
                ])
            }
        }

        // --- OAuth: authorization endpoint (PKCE, JSON — the agent path) -----
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

        // --- OAuth: token endpoint (code exchange + refresh rotation) --------
        router.post("/oauth/token") { request, context in
            let body = try await request.decode(as: TokenRequest.self, context: context)
            do {
                let issued: IssuedTokens
                switch body.grantType {
                case "authorization_code":
                    guard let code = body.code, let verifier = body.codeVerifier,
                          let redirectURI = body.redirectURI else {
                        return json(APIError(
                            error: "invalid_request",
                            errorDescription: "code, codeVerifier and redirectURI are required"
                        ), status: .badRequest)
                    }
                    issued = try oauth.token(
                        code: code, codeVerifier: verifier,
                        clientID: body.clientID, redirectURI: redirectURI
                    )
                case "refresh_token":
                    guard let refreshToken = body.refreshToken else {
                        return json(APIError(
                            error: "invalid_request",
                            errorDescription: "refreshToken is required"
                        ), status: .badRequest)
                    }
                    issued = try oauth.refresh(refreshToken: refreshToken, clientID: body.clientID)
                default:
                    return json(APIError(error: "unsupported_grant_type", errorDescription: nil),
                                status: .badRequest)
                }
                return json(TokenResponse(
                    accessToken: issued.access.value,
                    tokenType: "Bearer",
                    expiresIn: Int(issued.access.expiresAt.timeIntervalSinceNow),
                    scope: issued.access.scopes.sorted().joined(separator: " "),
                    refreshToken: issued.refreshToken
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

    // MARK: - Front-channel helpers

    /// Percent-decoded query values via URLComponents — one URL parser in the
    /// whole flow, the same one the client uses to build the request.
    static func queryValues(_ request: Request) -> [String: String] {
        guard let components = URLComponents(string: request.uri.description) else { return [:] }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name] = item.value ?? ""
        }
        return values
    }

    /// Parses an `application/x-www-form-urlencoded` body (the consent form).
    static func formValues(_ request: Request) async throws -> [String: String] {
        var buffer = try await request.body.collect(upTo: 64 * 1024)
        let raw = buffer.readString(length: buffer.readableBytes) ?? ""
        var values: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = formDecode(parts[0]) else { continue }
            values[key] = parts.count > 1 ? (formDecode(parts[1]) ?? "") : ""
        }
        return values
    }

    static func formDecode(_ component: Substring) -> String? {
        component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// 302 back to the client's redirect URI. URLComponents does the escaping
    /// and is happy with custom schemes (drachma://…). Only reached after the
    /// redirect URI has been validated against the client's registration.
    static func redirect(_ redirectURI: String, query: [(String, String?)]) -> Response {
        var components = URLComponents(string: redirectURI)
        var items = components?.queryItems ?? []
        for (name, value) in query {
            if let value { items.append(URLQueryItem(name: name, value: value)) }
        }
        components?.queryItems = items
        var headers = HTTPFields()
        headers[.location] = components?.string ?? redirectURI
        return Response(status: .found, headers: headers, body: ResponseBody())
    }

    static func html(_ body: String, status: HTTPResponse.Status) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(string: body)))
    }

    /// Everything user- or client-supplied is escaped before it touches HTML —
    /// the consent page must not be an XSS vector.
    static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func page(_ title: String, _ inner: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(htmlEscape(title))</title>
        <style>
          body { font: -apple-system-body, sans-serif; margin: 0; padding: 2rem 1.25rem;
                 display: flex; justify-content: center; }
          main { max-width: 22rem; width: 100%; }
          h1 { font-size: 1.3rem; }
          p, li { line-height: 1.45; }
          code { background: rgba(127,127,127,.15); padding: .1rem .3rem; border-radius: .3rem; }
          button { width: 100%; padding: .8rem; margin-top: .6rem; border-radius: .6rem;
                   border: 1px solid rgba(127,127,127,.4); font-size: 1rem; }
          button.approve { background: #0a84ff; border-color: #0a84ff; color: white; }
        </style></head>
        <body><main>\(inner)</main></body></html>
        """
    }

    static func errorPage(_ message: String) -> String {
        page("Drachma — error", "<h1>Can’t continue</h1><p>\(htmlEscape(message))</p>")
    }

    /// The consent screen. The request parameters ride along as hidden fields
    /// and are re-validated on POST — the form is a courier, not an authority.
    static func consentPage(_ params: AuthorizePageParams) -> String {
        let scopeList = params.scopes.sorted()
            .map { "<li><code>\(htmlEscape($0))</code></li>" }
            .joined()
        let hidden = [
            ("response_type", params.responseType),
            ("client_id", params.clientID),
            ("redirect_uri", params.redirectURI),
            ("code_challenge", params.codeChallenge),
            ("code_challenge_method", params.codeChallengeMethod),
            ("scope", params.scopeRaw),
            ("state", params.state ?? ""),
        ]
        .map { #"<input type="hidden" name="\#($0.0)" value="\#(htmlEscape($0.1))">"# }
        .joined(separator: "\n          ")

        return page("Connect to Drachma", """
        <h1>Connect to Drachma</h1>
        <p><code>\(htmlEscape(params.clientID))</code> is asking to:</p>
        <ul>\(scopeList)</ul>
        <p>Approving sends a one-time code back to the app. No password exists here — this demo authorizes the device itself.</p>
        <form method="post" action="/oauth/approve">
          \(hidden)
          <button class="approve" name="action" value="approve">Approve</button>
          <button name="action" value="deny">Deny</button>
        </form>
        """)
    }
}
