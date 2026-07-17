import SwiftUI

/// The Connect screen: sign in to your own drachma-server with OAuth 2.1
/// code + PKCE, then exercise the grant — protected call, rotation,
/// disconnect. Every step narrates itself in the log, because this screen
/// exists to make the invisible parts of OAuth visible.
public struct ConnectView: View {
    @Bindable private var model: ConnectViewModel

    public init(model: ConnectViewModel) {
        self._model = Bindable(model)
    }

    public var body: some View {
        Form {
            Section {
                TextField("http://192.168.0.10:8080", text: $model.serverURLText)
                    .autocorrectionDisabled()
                    .disabled(model.phase == .connecting)

                switch model.phase {
                case .disconnected, .failed:
                    Button {
                        Task { await model.connect() }
                    } label: {
                        Label("Connect", systemImage: "person.badge.key")
                    }
                case .connecting:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for the sign-in sheet…")
                            .foregroundStyle(.secondary)
                    }
                case .connected:
                    Button(role: .destructive) {
                        Task { await model.disconnect() }
                    } label: {
                        Label("Disconnect", systemImage: "person.badge.key.fill")
                    }
                }
            } header: {
                Text("Your drachma-server")
            } footer: {
                Text("Authorization Code + PKCE through the system sheet. The app never handles credentials — it sends a one-time code plus a proof only this device holds.")
            }

            if case .failed(let message) = model.phase {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }

            if case .connected(let grant) = model.phase {
                Section {
                    LabeledContent("Access token") {
                        Text("…\(grant.accessTokenSuffix)").monospaced()
                    }
                    LabeledContent("Scope") { Text(grant.scope) }
                    LabeledContent("Expires") { Text(grant.expiresAt, style: .relative) }
                    LabeledContent("Refresh token") {
                        Text(grant.hasRefreshToken ? "in Keychain" : "none")
                    }
                    Button {
                        Task { await model.refreshNow() }
                    } label: {
                        Label("Rotate now", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("Grant")
                } footer: {
                    Text("Refresh tokens are single-use: each rotation kills the last one. Replaying a dead one revokes the whole family server-side — watch the suffix change.")
                }

                Section {
                    Button {
                        Task { await model.fetchRate() }
                    } label: {
                        Label("GET /v1/rates with Bearer", systemImage: "lock.open")
                    }
                    if let rate = model.rateText {
                        Text(rate).font(.callout)
                    }
                } header: {
                    Text("Protected call")
                } footer: {
                    Text("If the access token is within 30s of expiry, the session refreshes once — single-flight — before the request goes out.")
                }
            }

            if !model.activityLog.isEmpty {
                Section("What just happened") {
                    ForEach(Array(model.activityLog.enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Connect")
        .task { await model.restore() }
    }
}
