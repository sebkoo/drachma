/// Where the app can navigate. Cases are added when their screens are —
/// history arrived first; settings will follow the same way.
public enum Route: Hashable, Sendable {
    case history(base: String, quote: String)
}
