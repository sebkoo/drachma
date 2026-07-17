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
        ratesClient: any PairRatesProviding = CachedPairRatesClient(wrapping: CompositeRatesClient())
    ) {
        _converter = State(initialValue: ConverterViewModel(ratesClient: ratesClient))
    }

    public var body: some View {
        NavigationStack(path: Bindable(coordinator).path) {
            ConverterView(model: converter, favorites: favorites) {
                coordinator.push(.history(base: converter.fromCurrency, quote: converter.toCurrency))
            }
            .navigationTitle("Drachma")
            .toolbar {
                ToolbarItem {
                    Button {
                        coordinator.push(.connect)
                    } label: {
                        Label("Connect", systemImage: "person.badge.key")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history(let base, let quote):
                    HistoryView(model: HistoryViewModel(
                        seriesClient: FrankfurterClient(),
                        base: base,
                        quote: quote
                    ))
                case .connect:
                    // State lives in the Keychain, not the view model — a
                    // fresh model per visit restores from storage.
                    ConnectView(model: ConnectViewModel())
                }
            }
            .task {
                // Screenshot/UI-automation hooks — simctl can launch but not
                // tap, so these land the app on a scene without a human.
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--open-history") {
                    coordinator.push(.history(base: converter.fromCurrency, quote: converter.toCurrency))
                }
                if arguments.contains("--open-connect") {
                    coordinator.push(.connect)
                }
                if arguments.contains("--demo-vnd-check") {
                    converter.toCurrency = "VND"
                    converter.quotedRateText = "24500"
                    await converter.load()
                }
            }
        }
    }
}
