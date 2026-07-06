# Drachma iOS app — MVVM-Coordinator layout

The Xcode project will be created here (Xcode 16 buildable folders adopt this
on-disk structure directly). Roles:

| Folder | MVVM-C role |
|---|---|
| `App/` | Entry point (`DrachmaApp`) and the composition root — builds the object graph, injects `DrachmaCore` clients into view models. |
| `Coordinator/` | Navigation owner: `Route` (where you can go) + `AppCoordinator` (`@Observable`, drives `NavigationStack`/sheets). Starts as a light router; grows into child coordinators only if flows multiply (onboarding, paywall). |
| `ViewModels/` | `@Observable` view models (`ConverterViewModel`, `FavoritesViewModel`, `SettingsViewModel`) — consume `DrachmaCore`, expose display state, never import SwiftUI views. |
| `Views/` | SwiftUI views — declarative, dumb, bound to view models; navigation is requested through the coordinator, never performed inline. |
| `Support/` | Cross-cutting seams: `EntitlementProviding` (free/Pro gate), formatters, environment helpers. |

The "M" of MVVM lives outside this folder on purpose: `DrachmaCore` (repo root)
is a platform-agnostic Swift package shared by the app, widgets, and the
`drachma-mcp` server — one core, every surface.
