# Drachma

![CI](https://github.com/sebkoo/drachma/actions/workflows/ci.yml/badge.svg)

Live currency conversion for humans **and** AI agents — a native iOS app and a Swift MCP server sharing one keyless public data source: the European Central Bank's reference rates, via the [Frankfurter API](https://frankfurter.dev).

No API keys. No accounts. No tracking.

## Manifesto

Exchange rates are public data. Most apps put them behind keys, quotas, ads, and consent walls anyway. Drachma refuses all of it:

- **No ads. Ever.** Not in the free tier, not "removable" ones. An ad that covers your keypad is not a business model.
- **No accounts, no tracking.** A currency converter does not need to know who you are. The code is open, so this claim is auditable — not a privacy-policy promise.
- **Honest rates, timestamped.** Every number shows exactly what it is and how old it is: *"ECB reference rate, Fri 16:00 CET."* These are daily reference rates — great for travel, remittance, and invoicing; not trading quotes. You will never see the word "live" here unless it's true.
- **The free tier is free forever.** The core job — converting money, offline, with your favorite pairs — will never move behind a paywall. Nothing that is free today becomes paid tomorrow.

## Why not just google it?

For a one-off "usd to eur", Google is fine — honestly. Drachma is for the **repeated-use** jobs:

| You are… | Drachma gives you |
|---|---|
| A traveler converting street prices all day | A Home/Lock Screen **widget** pinned to your pair — zero taps — and **offline** cached rates when there's no signal |
| A remitter watching one pair every morning | **Rate alerts** and a history chart, so you send on a good day |
| A cross-border freelancer invoicing monthly | A multi-pair dashboard with paste-friendly, as-you-type conversion |
| An AI agent (Claude, etc.) | The **`drachma-mcp` server** — FX tools inside the conversation, no key to provision |

## The MCP server

`drachma-mcp` is the AI-agent door to the same kitchen. Any MCP-compatible client gets three tools — `convert`, `latest_rates`, `historical_rates` — with zero configuration: nothing to sign up for, no key to paste.

```sh
# once released:
claude mcp add drachma -- drachma-mcp
```

## Layout

```
drachma/
├── DrachmaCore/           # the "M" — one shared Swift package, every surface
│   └── Sources/
│       ├── Models/        #   Rate, CurrencyPair, Money, RatesSnapshot
│       ├── Networking/    #   FrankfurterClient (protocol + URLSession live impl)
│       └── Caching/       #   RatesCache actor — last-good rates + staleness
├── mcp/                   # drachma-mcp executable (MCP Swift SDK, stdio)
├── ios/Drachma/           # SwiftUI app — MVVM-Coordinator
│   ├── App/               #   entry point + composition root
│   ├── Coordinator/       #   Route + AppCoordinator (@Observable router)
│   ├── ViewModels/        #   @Observable view models
│   ├── Views/             #   declarative views; navigation via the coordinator
│   └── Support/           #   EntitlementProviding (free/Pro seam), formatters
└── docs/                  # screenshots, decisions
```

One deliberate choice: the Model layer lives outside the app as a package, so the app, its widgets, and the MCP server consume identical models, networking, and caching. The coordinator starts as a ~30-line router and grows only if flows multiply.

## Pro, and how an open-source app can have one

A paid **Drachma Pro** tier will eventually fund development: unlimited widgets, unlimited rate alerts, long-range history charts, unlimited favorite pairs, and the Apple Watch app. The free tier stays genuinely excellent — see the pledge above.

And because Drachma is fully open source — Pro code included — you can always build it yourself with Xcode and have everything, free. Buying it on the App Store is the convenient path: a signed build, automatic updates, and a way to keep an ad-free, tracker-free converter alive. Both are legitimate. That's the deal.

## Roadmap

- [x] Repo, package scaffold, MVVM-Coordinator layout
- [x] `DrachmaCore`: models + Frankfurter client + tests
- [x] `drachma-mcp`: `convert`, `latest_rates`, `historical_rates` (MCP Swift SDK)
- [x] CI (GitHub Actions): build + test on every push
- [ ] iOS app: converter screen, favorite pairs, offline last-good cache with visible timestamps, paste support, dark mode, currency symbols
- [ ] Free tastes: 1 widget, 1 rate alert, 7-day chart
- [ ] App Store release + Drachma Pro (unlimited widgets/alerts/pairs, full charts, Apple Watch)
- [ ] Localization (EU languages first — it's ECB data, after all)

Issues are the living version of this list.

## The name

The drachma was the money of the ancient Mediterranean. Athens' silver "owl" tetradrachms were struck to one trusted standard and traded far beyond Greece — hoarded from Egypt to Bactria — making them the closest thing antiquity had to a world currency. A fitting emblem for an app whose whole job is moving between currencies. Pronounced **DRAK-ma** (Korean: 드라크마).

## How it's built

Built in the open with [Claude Code](https://claude.com/claude-code) as an AI pair — the same workflow as [Pulse](https://github.com/sebkoo/Pulse): AI-assisted, every line reviewed before it lands. Small, atomic commits; each one builds and tests green.

## Data

Rates are the ECB's daily reference rates served by [Frankfurter](https://frankfurter.dev) (open source, no key required). Rates update on ECB working days around 16:00 CET — so weekend numbers are Friday's, and Drachma says so on screen rather than pretending otherwise. They are reference rates, not tradable quotes.

## License

MIT — see [LICENSE](LICENSE).
