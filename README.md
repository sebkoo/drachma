# Drachma

Live currency conversion for humans **and** AI agents — a native iOS app and a Swift MCP server sharing one keyless public data source: the European Central Bank's reference rates, via the [Frankfurter API](https://frankfurter.dev).

No API keys. No accounts. No tracking.

## Why

Exchange rates are public data, but most apps put them behind keys, quotas, and ads. Drachma keeps the whole path open:

- **iOS app** (SwiftUI) — convert instantly, keep favorite pairs, see where a rate has been.
- **MCP server** (`drachma-mcp`, Swift) — give any MCP-compatible agent (Claude, etc.) live FX tools: `convert`, `latest_rates`, `historical`. Zero-config: no key to provision, nothing to sign up for.

Both are powered by the same Swift package — one core, every surface.

## Planned layout

```
drachma/
├── DrachmaCore/   # Swift package: models, Frankfurter client, cache (shared by app, widgets, MCP)
├── mcp/           # drachma-mcp executable (MCP Swift SDK, stdio)
├── ios/           # SwiftUI app (MVVM, offline-first last-good cache)
└── docs/          # screenshots, decisions
```

## The name

The drachma was the money of the ancient Mediterranean. Athens' silver "owl" tetradrachms were struck to one trusted standard and traded far beyond Greece — hoarded from Egypt to Bactria — making them the closest thing antiquity had to a world currency. A fitting emblem for an app whose whole job is moving between currencies. Pronounced **DRAK-ma** (Korean: 드라크마).

## Status

Bootstrapping — follow the commit history to watch it grow. Small, atomic commits; each one builds and tests green.

## How it's built

Built in the open with [Claude Code](https://claude.com/claude-code) as an AI pair — the same workflow as [Pulse](https://github.com/sebkoo/Pulse): AI-assisted, every line reviewed before it lands.

## Data

Rates are the ECB's daily reference rates served by [Frankfurter](https://frankfurter.dev) (open source, no key required). Rates update on ECB working days around 16:00 CET; they are reference rates, not tradable quotes.

## License

MIT — see [LICENSE](LICENSE).
