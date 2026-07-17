/// Where the app can navigate. Cases are added when their screens are —
/// history arrived first, connect (the OAuth demo) second; settings will
/// follow the same way.
public enum Route: Hashable, Sendable {
    case history(base: String, quote: String)
    case connect
}
