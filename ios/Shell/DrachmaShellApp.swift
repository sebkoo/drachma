import SwiftUI
import DrachmaApp

// The thin @main wrapper the package was designed for — everything real
// lives in DrachmaApp (see DrachmaRootView, the composition root).
@main
struct DrachmaShellApp: App {
    var body: some Scene {
        WindowGroup {
            DrachmaRootView()
        }
    }
}
