import SwiftUI
import DrachmaCore

public struct ConverterView: View {
    private enum PickerTarget: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    @Bindable private var model: ConverterViewModel
    @State private var pickerTarget: PickerTarget?
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

                Button {
                    pickerTarget = .from
                } label: {
                    LabeledContent("From") { Text(model.fromCurrency) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    pickerTarget = .to
                } label: {
                    LabeledContent("To") { Text(model.toCurrency) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await model.swapCurrencies() }
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                }
            }

            Section {
                result

                if case .loaded = model.state, model.isHistoryAvailable, let onShowHistory {
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
                TextField(
                    "1 \(model.fromCurrency) = ? \(model.toCurrency)",
                    text: $model.quotedRateText
                )

                if let check = model.rateCheck {
                    VStack(alignment: .leading, spacing: 4) {
                        let percent = abs((check.markupPercent as NSDecimalNumber).doubleValue)
                        Text("\(percent, specifier: "%.1f")% \(check.markupPercent >= 0 ? "worse" : "better") than mid-market")
                            .font(.headline)
                        Text(check.verdict)
                            .foregroundStyle(.secondary)
                        if check.looksFlipped {
                            Text("These numbers look flipped — did they quote \(model.fromCurrency) per \(model.toCurrency)?")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Rate check")
            } footer: {
                Text("Type the rate a counter or kiosk offers you — today's mid-market rate is the yardstick. No data leaves the device.")
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
        .onChange(of: model.toCurrency) {
            // The pair decides the source (ECB vs community), so quote
            // changes reload too.
            Task { await model.load() }
        }
        .sheet(item: $pickerTarget) { target in
            CurrencySelectorView(
                title: target == .from ? "From" : "To",
                options: model.currencyOptions
            ) { code in
                switch target {
                case .from: model.fromCurrency = code
                case .to: model.toCurrency = code
                }
            }
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
        if let date = model.rateDate, let source = model.sourceLabel {
            // The manifesto on screen: every number says which day it belongs
            // to — and which system it came from.
            Text("\(source) · \(date) · not a tradable quote")
        }
    }
}
