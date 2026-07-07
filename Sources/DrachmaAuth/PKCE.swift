import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Proof Key for Code Exchange (RFC 7636) — the OAuth 2.1 defense against
/// authorization-code interception. The client keeps a secret `verifier` and
/// sends only its SHA-256 `challenge` up front; the token exchange later
/// proves possession of the verifier.
public enum PKCE {
    public static let method = "S256"

    /// A high-entropy code verifier (RFC 7636 §4.1): 32 random bytes, base64url.
    public static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = rng.next() }
        return base64URLEncode(Data(bytes))
    }

    /// The S256 challenge for a verifier: base64url(SHA256(verifier)).
    /// Returns nil for any method other than S256 — OAuth 2.1 forbids `plain`.
    public static func challenge(for verifier: String, method: String = method) -> String? {
        guard method == Self.method else { return nil }
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Constant-time-ish verification that a verifier matches a stored challenge.
    public static func verify(verifier: String, matches challenge: String, method: String = method) -> Bool {
        guard let computed = Self.challenge(for: verifier, method: method) else { return false }
        return computed == challenge
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
