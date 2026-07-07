import Observation

/// Owns navigation state. Sized to the app: push/pop arrived together with
/// the first `Route` case (history), exactly as promised when the compiler
/// proved they couldn't run before it existed. Child coordinators come only
/// if flows multiply (onboarding, paywall).
@Observable @MainActor
public final class AppCoordinator {
    public var path: [Route] = []

    public init() {}

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        _ = path.popLast()
    }
}
