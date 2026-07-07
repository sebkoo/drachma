import SwiftUI
import DrachmaCore

public struct ConverterView: View {
    @Bindable private var model: ConverterViewModel
    private let favorites: FavoritesStore
    private let staticControls: Bool
    /// The view requests navigation; whoever owns the coordinator decides.
    private let onShowHistory: (() -> Void)?

    /// `staticControls` renders the same data through a pure-SwiftUI layout so
    /// ImageRenderer can snapshot it. Lesson carried over from Pulse and
    /// extended here: ImageRenderer draws neither the platform-backed controls
    /// (TextField, Picker, Button) nor `Form` itself.
    public init(
        model: ConverterViewModel,
        favorites: FavoritesStore = FavoritesStore(),
        staticControls: Bool = false,
        onShowHistory: (() -> Void)? = nil
    ) {
        self._model = Bindable(model)
        self.favorites = favorites
        self.staticControls = staticControls
        self.onShowHistory = onShowHistory
    }

    public var body: some View {
        if staticControls {
            snapshotBody
        } else {
            formBody
        }
    }

    // MARK: - Interactive (the app)

    private var formBody: some View {
        Form {
            Section {
                TextField("Amount", text: $model.amountText)

                Picker("From", selection: $model.fromCurrency) {
                    ForEach(model.availableCurrencies, id: \.self) { Text($0) }
                }
                Picker("To", selection: $model.toCurrency) {
                    ForEach(model.availableCurrencies, id: \.self) { Text($0) }
                }

                Button {
                    Task { await model.swapCurrencies() }
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                }
            }

            Section {
                result

                if case .loaded = model.state, let onShowHistory {
                    Button {
                        onShowHistory()
                    } label: {
                        Label("7-day history", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            } footer: {
                honestFooter
            }

            Section {
                ForEach(favorites.pairs, id: \.self) { pair in
                    Button {
                        model.fromCurrency = pair.base
                        model.toCurrency = pair.quote
                    } label: {
                        HStack {
                            Text("\(pair.base) → \(pair.quote)")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            favorites.remove(pair)
                        }
                    }
                }

                let current = FavoritePair(base: model.fromCurrency, quote: model.toCurrency)
                Button {
                    favorites.add(current)
                } label: {
                    Label("Save this pair", systemImage: "star")
                }
                .disabled(favorites.isAtLimit || favorites.pairs.contains(current))
            } header: {
                Text("Favorites")
            } footer: {
                if favorites.isAtLimit {
                    // The seam made visible — honestly, before any paywall exists.
                    Text("The free tier holds 5 pairs. Unlimited pairs arrive with Pro.")
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.fromCurrency) {
            Task { await model.load() }
        }
    }

    // MARK: - Snapshot (pure SwiftUI, renderable)

    private var snapshotBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                staticRow("Amount", model.amountText)
                Divider().padding(.horizontal, 12)
                staticRow("From", model.fromCurrency)
                Divider().padding(.horizontal, 12)
                staticRow("To", model.toCurrency)
                Divider().padding(.horizontal, 12)
                HStack {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.tint)
                    Spacer()
                }
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))

            VStack(alignment: .leading, spacing: 8) {
                result
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))

            honestFooter
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func staticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - Shared

    @ViewBuilder
    private var result: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
        case .failed(let message):
            Text(message)
            Button("Retry") {
                Task { await model.load() }
            }
        case .loaded:
            if let amount = model.amount, let converted = model.convertedAmount {
                // .currency gives the right symbol and the right decimals per
                // currency ("₩1,538", "€87.60") — a top ask in competitor reviews.
                Text("\(amount.formatted(.currency(code: model.fromCurrency))) = \(converted.formatted(.currency(code: model.toCurrency)))")
                    .font(.title3.weight(.semibold))
            } else {
                Text("Enter a valid amount")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var honestFooter: some View {
        if let date = model.rateDate {
            // The manifesto on screen: every number says which day it belongs to.
            Text("ECB reference rate · \(date) · not a tradable quote")
        }
    }
}
