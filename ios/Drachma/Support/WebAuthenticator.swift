#if canImport(AuthenticationServices)
import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// ASWebAuthenticationSession as one async call: present the system sheet,
/// come back with the callback URL (or a typed cancel). The system sheet is
/// the point — the OS owns the browser context, so the app can't read what
/// happens inside it, and the user can see they're on *their* server.
@MainActor
public final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    public enum WebAuthError: Error, Equatable {
        case userCancelled
        case missingCallback
    }

    /// Uses the non-deprecated `Callback` API (iOS 17.4 / macOS 14.4) — the
    /// caller gates availability and explains itself on older systems.
    @available(iOS 17.4, macOS 14.4, *)
    public func authenticate(
        url: URL,
        callbackScheme: String,
        ephemeral: Bool = true
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { callbackURL, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    continuation.resume(throwing: code == .canceledLogin
                        ? WebAuthError.userCancelled
                        : error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WebAuthError.missingCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Ephemeral: no shared Safari cookies in, none left behind —
            // every demo run starts clean.
            session.prefersEphemeralWebBrowserSession = ephemeral
            session.start()
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
#if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.keyWindow ?? ASPresentationAnchor()
#elseif os(macOS)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
#endif
    }
}
#endif
