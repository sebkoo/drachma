import SwiftUI
import DrachmaCore

public struct ConverterView: View {
    @Bindable private var model: ConverterViewModel
    private let staticControls: Bool

    /// `staticControls` renders the same data through a pure-SwiftUI layout so
    /// ImageRenderer can snapshot it. Lesson carried over from Pulse and
    /// extended here: ImageRenderer draws neither the platform-backed controls
    /// (TextField, Picker, Button) nor `Form` itself.
    public init(model: ConverterViewModel, staticControls: Bool = false) {
        self._model = Bindable(model)
        self.staticControls = staticControls
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
            } footer: {
                honestFooter
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
            if let converted = model.convertedAmount {
                Text("\(model.amountText) \(model.fromCurrency) = \(converted.formatted()) \(model.toCurrency)")
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
