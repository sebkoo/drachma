import Observation

/// Owns navigation state. Sized to the app: today that is just the path —
/// push/pop arrive with the first `Route` case (history chart, settings),
/// and child coordinators only if flows multiply (onboarding, paywall).
@Observable @MainActor
public final class AppCoordinator {
    public var path: [Route] = []

    public init() {}
}
