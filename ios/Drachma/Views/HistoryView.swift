import SwiftUI
import Charts
import DrachmaCore

public struct HistoryView: View {
    private let model: HistoryViewModel

    public init(model: HistoryViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                    Button("Retry") {
                        Task { await model.load() }
                    }
                }
            case .loaded:
                VStack(alignment: .leading, spacing: 12) {
                    Chart(model.points) { point in
                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Rate", point.rateAsDouble)
                        )
                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Rate", point.rateAsDouble)
                        )
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(maxHeight: 280)

                    // The manifesto, on every surface: what the numbers are
                    // and which days they belong to.
                    Text("ECB reference rates · 1 \(model.base) in \(model.quote) · last 7 days (working days only)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("\(model.base) → \(model.quote)")
        .task { await model.load() }
    }
}
