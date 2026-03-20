import SwiftUI

@main
struct GlassdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var connectionStore = ConnectionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(connectionStore)
        }
    }
}

struct ContentView: View {
    @State private var selectedConnection: ConnectionProfile?
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        NavigationSplitView {
            ConnectionListView(selection: $selectedConnection)
        } detail: {
            if let connection = selectedConnection {
                TerminalContainerView(profile: connection)
            } else if !sessionManager.sessions.isEmpty {
                SessionTabView()
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: Binding(
            get: { sessionManager.showConnectionPicker },
            set: { sessionManager.showConnectionPicker = $0 }
        )) {
            ConnectionPickerSheet { profile in
                Task {
                    await sessionManager.connect(to: profile)
                }
            }
        }
    }
}

/// Quick connection picker for new tab flow.
struct ConnectionPickerSheet: View {
    let onSelect: (ConnectionProfile) -> Void
    @Environment(ConnectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.connections) { profile in
                    Button {
                        onSelect(profile)
                        dismiss()
                    } label: {
                        ConnectionRow(profile: profile)
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Glassdeck")
                .font(.largeTitle.bold())
            Text("Select a connection or create a new one")
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
