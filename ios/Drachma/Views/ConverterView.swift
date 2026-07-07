import SwiftUI
import DrachmaCore

public struct ConverterView: View {
    @Bindable private var model: ConverterViewModel

    public init(model: ConverterViewModel) {
        self._model = Bindable(model)
    }

    public var body: some View {
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
            } footer: {
                if let date = model.rateDate {
                    // The manifesto on screen: every number says which day it belongs to.
                    Text("ECB reference rate · \(date) · not a tradable quote")
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.fromCurrency) {
            Task { await model.load() }
        }
    }
}
