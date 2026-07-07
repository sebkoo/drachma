import SwiftUI
import DrachmaCore

/// The composition root: builds the object graph and owns the navigation
/// container. The Xcode app shell stays a thin `@main` wrapper around this —
/// the package owns the app.
public struct DrachmaRootView: View {
    @State private var coordinator = AppCoordinator()
    @State private var converter: ConverterViewModel
    @State private var favorites = FavoritesStore()

    public init(
        ratesClient: any RatesClient = CachedRatesClient(wrapping: FrankfurterClient())
    ) {
        _converter = State(initialValue: ConverterViewModel(ratesClient: ratesClient))
    }

    public var body: some View {
        NavigationStack(path: Bindable(coordinator).path) {
            ConverterView(model: converter, favorites: favorites)
                .navigationTitle("Drachma")
        }
    }
}
