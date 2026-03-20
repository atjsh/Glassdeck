import SwiftUI

@main
struct GlassdeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var selectedConnection: ConnectionProfile?

    var body: some View {
        NavigationSplitView {
            ConnectionListView(selection: $selectedConnection)
        } detail: {
            if let connection = selectedConnection {
                TerminalContainerView(profile: connection)
            } else {
                WelcomeView()
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
