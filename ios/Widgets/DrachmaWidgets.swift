import WidgetKit
import SwiftUI
import AppIntents
import DrachmaCore

// The widget speaks the same manifesto: one pair, today's reference rate,
// honestly dated and sourced. Configure the pair by long-pressing the widget.

struct PairConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Currency Pair"
    static let description = IntentDescription("Choose the pair to track.")

    @Parameter(title: "From (ISO code)", default: "USD")
    var base: String

    @Parameter(title: "To (ISO code)", default: "EUR")
    var quote: String
}

struct RateEntry: TimelineEntry {
    let date: Date
    let base: String
    let quote: String
    let rate: Decimal?
    let rateDate: String?
    let source: RateSource?
}

struct RateProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RateEntry {
        RateEntry(
            date: .now, base: "USD", quote: "EUR",
            rate: Decimal(string: "0.876"), rateDate: "2026-07-06", source: .ecb
        )
    }

    func snapshot(for configuration: PairConfigurationIntent, in context: Context) async -> RateEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: PairConfigurationIntent, in context: Context) async -> Timeline<RateEntry> {
        let entry = await entry(for: configuration)
        // ECB publishes once per working day — a 6-hour cadence is plenty.
        let refresh = Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func entry(for configuration: PairConfigurationIntent) async -> RateEntry {
        let base = configuration.base.uppercased()
        let quote = configuration.quote.uppercased()
        let client = CachedPairRatesClient(wrapping: CompositeRatesClient())
        let snapshot = try? await client.latestRates(base: base, quote: quote)
        let rate = snapshot.flatMap { try? $0.convert(1, from: base, to: quote) }
        return RateEntry(
            date: .now, base: base, quote: quote,
            rate: rate, rateDate: snapshot?.date, source: snapshot?.source
        )
    }
}

struct RateWidgetView: View {
    var entry: RateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(entry.base) → \(entry.quote)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let rate = entry.rate {
                Text(rate.formatted(.number.precision(.significantDigits(5))))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.title2.weight(.bold))
            }

            Spacer(minLength: 0)

            if let rateDate = entry.rateDate {
                // The manifesto, even at glance size: date and source, always.
                Text("\(entry.source == .community ? "community" : "ECB") · \(rateDate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("offline — open the app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct RateWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "RateWidget",
            intent: PairConfigurationIntent.self,
            provider: RateProvider()
        ) { entry in
            RateWidgetView(entry: entry)
        }
        .configurationDisplayName("Rate")
        .description("One pair, today's reference rate, honestly dated.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DrachmaWidgetBundle: WidgetBundle {
    var body: some Widget {
        RateWidget()
    }
}
