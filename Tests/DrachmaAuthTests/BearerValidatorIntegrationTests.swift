import XCTest
import MCP
@testable import DrachmaAuth

/// Proves the authorization server actually secures an MCP HTTP endpoint:
/// build the SDK's resource-server `BearerTokenValidator` from an OAuthServer,
/// then run it against real HTTP requests. This is the seam that turns
/// drachma-mcp from a local stdio tool into an OAuth-protected HTTP server.
final class BearerValidatorIntegrationTests: XCTestCase {
    private let audience = "https://drachma.local/mcp"
    private let redirect = "http://127.0.0.1/callback"

    private func issuedToken(on server: OAuthServer) throws -> String {
        server.register(OAuthClient(id: "agent", redirectURIs: [redirect], allowedScopes: ["rates:read"]))
        let verifier = PKCE.generateCodeVerifier()
        let code = try server.authorize(
            clientID: "agent", redirectURI: redirect,
            codeChallenge: PKCE.challenge(for: verifier)!,
            codeChallengeMethod: PKCE.method, scope: ["rates:read"]
        )
        return try server.token(code: code, codeVerifier: verifier, clientID: "agent", redirectURI: redirect).value
    }

    /// Bridges our OAuthServer to the SDK's bearer validator, enforcing the
    /// `rates:read` scope.
    private func makeValidator(_ server: OAuthServer) -> BearerTokenValidator {
        BearerTokenValidator(
            resourceMetadataURL: URL(string: "\(audience)/.well-known/oauth-protected-resource")!,
            resourceIdentifier: URL(string: audience)!,
            tokenValidator: { token, _, _ in
                guard let access = server.introspect(token) else {
                    return .invalidToken(errorDescription: "Unknown or expired token")
                }
                guard access.scopes.contains("rates:read") else {
                    return .insufficientScope(requiredScopes: ["rates:read"])
                }
                return .valid(BearerTokenInfo(scopes: access.scopes, expiresAt: access.expiresAt))
            }
        )
    }

    private func context() -> HTTPValidationContext {
        HTTPValidationContext(httpMethod: "POST", isInitializationRequest: true)
    }

    func testMissingTokenIsChallengedWith401() {
        let validator = makeValidator(OAuthServer(audience: audience))
        let request = HTTPRequest(method: "POST", headers: [:])

        let response = validator.validate(request, context: context())

        XCTAssertEqual(response?.statusCode, 401)
    }

    func testGarbageTokenIsRejected() {
        let validator = makeValidator(OAuthServer(audience: audience))
        let request = HTTPRequest(method: "POST", headers: ["Authorization": "Bearer not-real"])

        XCTAssertEqual(validator.validate(request, context: context())?.statusCode, 401)
    }

    func testValidTokenPassesThePipeline() throws {
        let server = OAuthServer(audience: audience)
        let token = try issuedToken(on: server)
        let validator = makeValidator(server)
        let request = HTTPRequest(method: "POST", headers: ["Authorization": "Bearer \(token)"])

        // nil == the request is allowed through to the MCP handler.
        XCTAssertNil(validator.validate(request, context: context()))
    }

    func testTheValidatorComposesIntoTheHTTPTransportPipeline() async {
        // The real wiring: the transport accepts our bearer validator first in
        // its pipeline, so unauthenticated MCP calls never reach a tool.
        let validator = makeValidator(OAuthServer(audience: audience))
        let pipeline = StandardValidationPipeline(validators: [
            validator,
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
        ])
        let transport = StatelessHTTPServerTransport(validationPipeline: pipeline)

        let unauthenticated = HTTPRequest(
            method: "POST",
            headers: ["Accept": "application/json", "Content-Type": "application/json"],
            body: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.utf8)
        )
        let response = await transport.handleRequest(unauthenticated)

        XCTAssertEqual(response.statusCode, 401, "the transport rejects the call before any tool runs")
    }
}
